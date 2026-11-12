import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:fintrack_core/fintrack_core.dart';

import 'secret_store.dart';

/// Parâmetros do Argon2id. Ficam guardados com o PIN, para que uma mudança
/// futura dos valores por defeito não invalide PINs já criados.
class Argon2Params {
  const Argon2Params({
    this.memoryKiB = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  String encode() => '$memoryKiB,$iterations,$parallelism';

  static Argon2Params decode(String s) {
    final p = s.split(',').map(int.parse).toList();
    return Argon2Params(memoryKiB: p[0], iterations: p[1], parallelism: p[2]);
  }
}

typedef KeyDeriver = Future<Uint8List> Function(
  String pin,
  List<int> salt,
  Argon2Params params,
);

Future<Uint8List> _argon2id(String pin, List<int> salt, int m, int t, int p) async {
  final algorithm = Argon2id(
    parallelism: p,
    memory: m,
    iterations: t,
    hashLength: 64,
  );
  final key = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(pin)),
    nonce: salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}

/// Deriva 64 bytes do PIN fora da thread da interface.
Future<Uint8List> deriveInIsolate(String pin, List<int> salt, Argon2Params params) {
  final m = params.memoryKiB;
  final t = params.iterations;
  final p = params.parallelism;
  return Isolate.run(() => _argon2id(pin, salt, m, t, p));
}

sealed class UnlockResult {
  const UnlockResult();
}

/// PIN correto; [dataKey] é a chave de 256 bits que protege os dados locais.
class UnlockSuccess extends UnlockResult {
  const UnlockSuccess(this.dataKey);
  final Uint8List dataKey;
}

class UnlockWrongPin extends UnlockResult {
  const UnlockWrongPin(this.failures, this.wait);
  final int failures;
  final Duration wait;
}

/// Ainda dentro do tempo de espera; o PIN nem chegou a ser verificado.
class UnlockThrottled extends UnlockResult {
  const UnlockThrottled(this.remaining);
  final Duration remaining;
}

/// Limite de tentativas atingido.
class UnlockSignInRequired extends UnlockResult {
  const UnlockSignInRequired();
}

class LockStatus {
  const LockStatus(this.failures, this.remaining);
  final int failures;
  final Duration remaining;

  bool get signInRequired => LockoutPolicy.requiresAccountSignIn(failures);
}

/// Desbloqueio local por PIN de 6 dígitos.
///
/// O PIN nunca é guardado. O Argon2id deriva 64 bytes: os primeiros 32 são o
/// verificador; os últimos 32 cifram (AES-256-GCM) a chave de dados aleatória.
/// Tudo fica no Keystore/Keychain através do [SecretStore].
///
/// Limitação conhecida: o contador de tentativas e o tempo de espera usam o
/// relógio do dispositivo e são aplicados por software.
class PinVault {
  PinVault(
    this._store, {
    this.params = const Argon2Params(),
    DateTime Function()? now,
    KeyDeriver? deriver,
  })  : _now = now ?? DateTime.now,
        _derive = deriver ?? deriveInIsolate;

  static const _kParams = 'ft.pin.params';
  static const _kSalt = 'ft.pin.salt';
  static const _kVerifier = 'ft.pin.verifier';
  static const _kWrappedKey = 'ft.pin.wrappedKey';
  static const _kFailures = 'ft.pin.failures';
  static const _kLockedUntil = 'ft.pin.lockedUntil';

  final SecretStore _store;
  final Argon2Params params;
  final DateTime Function() _now;
  final KeyDeriver _derive;
  final _aes = AesGcm.with256bits();
  final _random = Random.secure();

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  Future<bool> hasPin() async => await _store.read(_kVerifier) != null;

  /// Cria o PIN e devolve a nova chave de dados.
  Future<Uint8List> createPin(String pin) async {
    final issue = PinPolicy.check(pin);
    if (issue != null) throw ArgumentError('PIN recusado: ${issue.name}');
    if (await hasPin()) throw StateError('Já existe um PIN');

    final salt = _randomBytes(16);
    final dataKey = _randomBytes(32);
    final derived = await _derive(pin, salt, params);
    final box = await _aes.encrypt(
      dataKey,
      secretKey: SecretKey(derived.sublist(32)),
      nonce: _aes.newNonce(),
    );

    await _store.write(_kParams, params.encode());
    await _store.write(_kSalt, base64Encode(salt));
    await _store.write(_kWrappedKey, base64Encode(box.concatenation()));
    await _store.delete(_kFailures);
    await _store.delete(_kLockedUntil);
    // O verificador é escrito por último: só então o PIN passa a existir.
    await _store.write(_kVerifier, base64Encode(derived.sublist(0, 32)));
    return dataKey;
  }

  Future<LockStatus> status() async {
    final failures = int.tryParse(await _store.read(_kFailures) ?? '') ?? 0;
    final untilMs = int.tryParse(await _store.read(_kLockedUntil) ?? '');
    var remaining = Duration.zero;
    if (untilMs != null) {
      final d = DateTime.fromMillisecondsSinceEpoch(untilMs).difference(_now());
      if (d > Duration.zero) {
        // Se o relógio recuou, a espera nunca excede a prevista para as falhas.
        final max = LockoutPolicy.delayAfter(failures);
        remaining = d > max ? max : d;
      }
    }
    return LockStatus(failures, remaining);
  }

  Future<UnlockResult> unlock(String pin) async {
    final current = await status();
    if (current.signInRequired) return const UnlockSignInRequired();
    if (current.remaining > Duration.zero) {
      return UnlockThrottled(current.remaining);
    }

    final saltB64 = await _store.read(_kSalt);
    final verifierB64 = await _store.read(_kVerifier);
    final wrappedB64 = await _store.read(_kWrappedKey);
    final paramsStr = await _store.read(_kParams);
    if (saltB64 == null || verifierB64 == null || wrappedB64 == null || paramsStr == null) {
      throw StateError('Não existe PIN configurado');
    }

    final derived = await _derive(
      pin,
      base64Decode(saltB64),
      Argon2Params.decode(paramsStr),
    );

    if (!_constantTimeEquals(derived.sublist(0, 32), base64Decode(verifierB64))) {
      final failures = current.failures + 1;
      await _store.write(_kFailures, '$failures');
      if (LockoutPolicy.requiresAccountSignIn(failures)) {
        return const UnlockSignInRequired();
      }
      final wait = LockoutPolicy.delayAfter(failures);
      if (wait > Duration.zero) {
        await _store.write(
          _kLockedUntil,
          '${_now().add(wait).millisecondsSinceEpoch}',
        );
      }
      return UnlockWrongPin(failures, wait);
    }

    await _store.delete(_kFailures);
    await _store.delete(_kLockedUntil);
    final box = SecretBox.fromConcatenation(
      base64Decode(wrappedB64),
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    final dataKey = await _aes.decrypt(
      box,
      secretKey: SecretKey(derived.sublist(32)),
    );
    return UnlockSuccess(Uint8List.fromList(dataKey));
  }

  /// Apaga o PIN e a chave de dados. Os dados cifrados com ela ficam ilegíveis.
  Future<void> reset() async {
    for (final k in [_kVerifier, _kWrappedKey, _kSalt, _kParams, _kFailures, _kLockedUntil]) {
      await _store.delete(k);
    }
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

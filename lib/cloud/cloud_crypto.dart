import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/pin_vault.dart';

Uint8List _random(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

/// Cifra ponta-a-ponta dos registos enviados para a nuvem.
///
/// Cada registo é cifrado no telemóvel com XChaCha20-Poly1305 e a chave de
/// dados do utilizador; o tipo e o identificador entram como dados
/// autenticados, para o servidor não poder trocar registos entre si.
class CloudCrypto {
  CloudCrypto(List<int> dataKey) : _key = SecretKey(List.unmodifiable(dataKey));

  final SecretKey _key;
  static final _aead = Xchacha20.poly1305Aead();

  static Uint8List newDataKey() => _random(32);

  Future<String> seal(String kind, String id, String json) async {
    final box = await _aead.encrypt(
      utf8.encode(json),
      secretKey: _key,
      nonce: _aead.newNonce(),
      aad: utf8.encode('$kind/$id'),
    );
    return base64Encode(box.concatenation());
  }

  Future<String> open(String kind, String id, String payload) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(payload),
        nonceLength: _aead.nonceLength,
        macLength: _aead.macAlgorithm.macLength,
      );
      return utf8.decode(await _aead.decrypt(box, secretKey: _key, aad: utf8.encode('$kind/$id')));
    } catch (_) {
      throw const FormatException('Registo da nuvem ilegível com esta chave');
    }
  }
}

/// A chave de dados guardada na nuvem vai sempre "embrulhada": cifrada com
/// uma chave derivada (Argon2id) da palavra-passe ou do código de recuperação.
class KeyWrap {
  static final _aes = AesGcm.with256bits();

  static Future<String> wrap(
    List<int> dataKey,
    String secret, {
    Argon2Params params = const Argon2Params(),
    KeyDeriver deriver = deriveInIsolate,
  }) async {
    final salt = _random(16);
    final k = await deriver(secret, salt, params);
    final box = await _aes.encrypt(dataKey, secretKey: SecretKey(k.sublist(0, 32)), nonce: _aes.newNonce());
    k.fillRange(0, k.length, 0);
    return jsonEncode({
      'kdf': 'argon2id',
      'params': params.encode(),
      'salt': base64Encode(salt),
      'box': base64Encode(box.concatenation()),
    });
  }

  /// Desembrulha; segredo errado dá [FormatException].
  static Future<Uint8List> unwrap(String wrapped, String secret, {KeyDeriver deriver = deriveInIsolate}) async {
    final j = jsonDecode(wrapped) as Map<String, Object?>;
    final k = await deriver(
      secret,
      base64Decode(j['salt']! as String),
      Argon2Params.decode(j['params']! as String),
    );
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(j['box']! as String),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      return Uint8List.fromList(await _aes.decrypt(box, secretKey: SecretKey(k.sublist(0, 32))));
    } on SecretBoxAuthenticationError {
      throw const FormatException('Segredo errado');
    } finally {
      k.fillRange(0, k.length, 0);
    }
  }
}

/// Código de recuperação: 160 bits aleatórios em 8 grupos de 4 caracteres
/// (sem letras ambíguas), ex.: K7QF-2MXA-...
class RecoveryCode {
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sem I, O, 0, 1

  static String generate() {
    final r = Random.secure();
    final chars = [for (var i = 0; i < 32; i++) _alphabet[r.nextInt(_alphabet.length)]];
    return [for (var i = 0; i < 32; i += 4) chars.sublist(i, i + 4).join()].join('-');
  }

  /// Aceita minúsculas, espaços e hífenes.
  static String normalize(String input) {
    final s = input.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    if (s.length != 32) return s;
    return [for (var i = 0; i < 32; i += 4) s.substring(i, i + 4)].join('-');
  }
}

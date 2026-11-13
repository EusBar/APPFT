import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/pin_vault.dart';
import 'snapshot.dart';

/// Cópia de segurança cifrada com palavra-passe (secção 18):
/// Argon2id deriva a chave da palavra-passe e AES-256-GCM cifra os dados.
/// Sem a palavra-passe, o ficheiro é ilegível — nem o FINTRACK o abre.
class EncryptedBackup {
  static const format = 'fintrack-encrypted-backup';
  static const minPasswordLength = 8;

  static final _aes = AesGcm.with256bits();

  static Uint8List _random(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  /// Cifra a cópia. [params] e [deriver] só mudam nos testes.
  static Future<Uint8List> encrypt(
    Snapshot snapshot,
    String password, {
    Argon2Params params = const Argon2Params(),
    KeyDeriver deriver = deriveInIsolate,
  }) async {
    if (password.length < minPasswordLength) {
      throw ArgumentError('A palavra-passe tem de ter pelo menos $minPasswordLength caracteres');
    }
    final salt = _random(16);
    final key = await deriver(password, salt, params);
    final plain = utf8.encode(jsonEncode(snapshot.toJson()));
    final box = await _aes.encrypt(plain, secretKey: SecretKey(key.sublist(0, 32)), nonce: _aes.newNonce());
    key.fillRange(0, key.length, 0);
    final envelope = {
      'format': format,
      'version': 1,
      'kdf': {'alg': 'argon2id', 'params': params.encode(), 'salt': base64Encode(salt)},
      'cipher': 'aes-256-gcm',
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'data': base64Encode(box.cipherText),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  /// Decifra e valida. Palavra-passe errada ou ficheiro alterado dão
  /// [FormatException] e nada é restaurado.
  static Future<Snapshot> decrypt(
    List<int> bytes,
    String password, {
    KeyDeriver deriver = deriveInIsolate,
  }) async {
    Map<String, Object?> envelope;
    try {
      envelope = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    } catch (_) {
      throw const FormatException('Ficheiro de cópia inválido');
    }
    if (envelope['format'] != format) throw const FormatException('Não é uma cópia cifrada do FINTRACK');
    final kdf = envelope['kdf']! as Map<String, Object?>;
    final params = Argon2Params.decode(kdf['params']! as String);
    final key = await deriver(password, base64Decode(kdf['salt']! as String), params);
    List<int> plain;
    try {
      plain = await _aes.decrypt(
        SecretBox(
          base64Decode(envelope['data']! as String),
          nonce: base64Decode(envelope['nonce']! as String),
          mac: Mac(base64Decode(envelope['mac']! as String)),
        ),
        secretKey: SecretKey(key.sublist(0, 32)),
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('Palavra-passe errada ou ficheiro alterado');
    } finally {
      key.fillRange(0, key.length, 0);
    }
    final snapshot = Snapshot.fromJson(jsonDecode(utf8.decode(plain)) as Map<String, Object?>);
    snapshot.validate();
    return snapshot;
  }
}

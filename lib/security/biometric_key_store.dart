import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/foundation.dart';

/// Resultado de uma tentativa de desbloqueio por biometria.
sealed class BiometricResult {
  const BiometricResult();
}

class BiometricKey extends BiometricResult {
  const BiometricKey(this.dataKey);
  final Uint8List dataKey;
}

/// O utilizador cancelou ou escolheu usar o PIN.
class BiometricCancelled extends BiometricResult {
  const BiometricCancelled();
}

/// A chave deixou de ser legível (ex.: impressões digitais alteradas).
class BiometricInvalidated extends BiometricResult {
  const BiometricInvalidated();
}

/// Guarda uma cópia da chave de dados protegida pela biometria do telemóvel.
///
/// A cópia fica no Android Keystore / iOS Keychain com autenticação
/// biométrica obrigatória em cada leitura: sem impressão digital ou rosto,
/// nem o próprio app a consegue ler. Se as biometrias do telemóvel mudarem,
/// a chave é invalidada pelo sistema e volta a ser preciso o PIN.
abstract interface class BiometricKeyStore {
  Future<bool> isAvailable();
  Future<void> save(Uint8List dataKey);
  Future<BiometricResult> load();
  Future<void> clear();
}

class DeviceBiometricKeyStore implements BiometricKeyStore {
  const DeviceBiometricKeyStore();

  static const _name = 'fintrack_data_key';

  static const _prompt = PromptInfo(
    androidPromptInfo: AndroidPromptInfo(
      title: 'Desbloquear o FINTRACK',
      subtitle: 'Use a impressão digital ou o rosto',
      negativeButton: 'Usar PIN',
      confirmationRequired: false,
    ),
    iosPromptInfo: IosPromptInfo(
      saveTitle: 'Ativar o desbloqueio do FINTRACK',
      accessTitle: 'Desbloquear o FINTRACK',
    ),
  );

  Future<BiometricStorageFile> _file() => BiometricStorage().getStorage(
        _name,
        options: StorageFileInitOptions(),
        promptInfo: _prompt,
      );

  @override
  Future<bool> isAvailable() async {
    try {
      return await BiometricStorage().canAuthenticate() == CanAuthenticateResponse.success;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> save(Uint8List dataKey) async {
    final hex = [for (final b in dataKey) b.toRadixString(16).padLeft(2, '0')].join();
    await (await _file()).write(hex);
  }

  @override
  Future<BiometricResult> load() async {
    try {
      final hex = await (await _file()).read();
      if (hex == null || hex.length != 64) return const BiometricInvalidated();
      return BiometricKey(Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
      ]));
    } on AuthException catch (e) {
      if (e.code == AuthExceptionCode.userCanceled ||
          e.code == AuthExceptionCode.canceled ||
          e.code == AuthExceptionCode.timeout) {
        return const BiometricCancelled();
      }
      return const BiometricInvalidated();
    } catch (_) {
      return const BiometricInvalidated();
    }
  }

  @override
  Future<void> clear() async {
    try {
      await (await _file()).delete();
    } catch (_) {
      // Nada guardado ou chave já invalidada: não há o que apagar.
    }
  }
}

/// Implementação em memória, só para testes.
@visibleForTesting
class MemoryBiometricKeyStore implements BiometricKeyStore {
  MemoryBiometricKeyStore({this.available = true});

  bool available;
  Uint8List? stored;
  BiometricResult? nextResult;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> save(Uint8List dataKey) async => stored = Uint8List.fromList(dataKey);

  @override
  Future<BiometricResult> load() async {
    final forced = nextResult;
    if (forced != null) return forced;
    final s = stored;
    return s == null ? const BiometricInvalidated() : BiometricKey(Uint8List.fromList(s));
  }

  @override
  Future<void> clear() async => stored = null;
}

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Resultado de uma tentativa de desbloqueio por biometria.
sealed class BiometricResult {
  const BiometricResult();
}

class BiometricKey extends BiometricResult {
  const BiometricKey(this.dataKey);
  final Uint8List dataKey;
}

/// O utilizador cancelou, escolheu usar o PIN ou a biometria está
/// temporariamente bloqueada pelo sistema.
class BiometricCancelled extends BiometricResult {
  const BiometricCancelled();
}

/// A chave deixou de ser legível (ex.: impressões digitais alteradas).
class BiometricInvalidated extends BiometricResult {
  const BiometricInvalidated();
}

/// Guarda uma cópia da chave de dados protegida pela biometria do telemóvel.
///
/// A cópia fica cifrada com uma chave do Android Keystore / iOS Keychain que
/// exige autenticação biométrica forte em cada leitura: sem impressão digital
/// ou rosto, nem o próprio app a consegue ler. Se as biometrias do telemóvel
/// mudarem, o sistema invalida a chave e volta a ser preciso o PIN.
abstract interface class BiometricKeyStore {
  Future<bool> isAvailable();
  Future<void> save(Uint8List dataKey);
  Future<BiometricResult> load();
  Future<void> clear();
}

class DeviceBiometricKeyStore implements BiometricKeyStore {
  const DeviceBiometricKeyStore();

  static const _key = 'ft.bio.dataKey';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions.biometric(
      // Cancelar a impressão digital conta como erro: nunca apagar por isso.
      resetOnError: false,
      enforceBiometrics: true,
      requireBiometricsPerOperation: true,
      biometricType: AndroidBiometricType.strongBiometricOnly,
      storageNamespace: 'fintrack_biometric',
      biometricPromptTitle: 'Desbloquear o FINTRACK',
      biometricPromptSubtitle: 'Use a impressão digital ou o rosto',
      biometricPromptNegativeButton: 'Usar PIN',
    ),
    iOptions: IOSOptions(
      accountName: 'fintrack_biometric',
      accessibility: KeychainAccessibility.unlocked_this_device,
      accessControlFlags: [AccessControlFlag.biometryCurrentSet],
    ),
  );

  /// A disponibilidade real só se sabe ao gravar: sem biometria registada,
  /// [save] falha e a ativação é recusada.
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> save(Uint8List dataKey) async {
    final hex = [for (final b in dataKey) b.toRadixString(16).padLeft(2, '0')].join();
    await _storage.write(key: _key, value: hex);
  }

  @override
  Future<BiometricResult> load() async {
    try {
      final hex = await _storage.read(key: _key);
      if (hex == null || hex.length != 64) return const BiometricInvalidated();
      return BiometricKey(Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
      ]));
    } catch (e) {
      return isCancellation(e.toString())
          ? const BiometricCancelled()
          : const BiometricInvalidated();
    }
  }

  /// Erros do pedido biométrico (cancelar, "Usar PIN", bloqueio temporário)
  /// não invalidam a chave; o resto (ex.: chave invalidada pelo sistema) sim.
  @visibleForTesting
  static bool isCancellation(String error) {
    final e = error.toLowerCase();
    return e.contains('biometric authentication error') ||
        e.contains('cancel') ||
        e.contains('-128');
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
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

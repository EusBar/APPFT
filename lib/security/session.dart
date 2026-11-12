import 'dart:typed_data';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/sqlcipher_store.dart';
import 'biometric_key_store.dart';
import 'pin_vault.dart';
import 'secret_store.dart';

final secretStoreProvider = Provider<SecretStore>(
  (ref) => const KeystoreSecretStore(),
);

final pinVaultProvider = Provider<PinVault>(
  (ref) => PinVault(ref.watch(secretStoreProvider)),
);

final localStoreFactoryProvider = Provider<LocalStoreFactory>(
  (ref) => const SqlCipherStoreFactory(),
);

final biometricKeyStoreProvider = Provider<BiometricKeyStore>(
  (ref) => const DeviceBiometricKeyStore(),
);

/// Resultado de ativar a biometria.
enum BiometricSetup { enabled, wrongPin, unavailable, failed }

enum SessionStatus { loading, needsPin, locked, onboarding, unlocked }

class SessionState {
  const SessionState({
    required this.status,
    this.discreet = false,
    this.autoLock = AutoLockSetting.oneMinute,
    this.profile,
    this.biometricEnabled = false,
  });

  final SessionStatus status;

  /// Modo discreto: todos os valores ficam ocultos.
  final bool discreet;

  /// Tempo em segundo plano até bloquear.
  final AutoLockSetting autoLock;

  /// Só existe com o app desbloqueado e o onboarding feito.
  final Profile? profile;

  /// Desbloqueio por impressão digital ou rosto ativado neste telemóvel.
  final bool biometricEnabled;

  SessionState copyWith({
    SessionStatus? status,
    bool? discreet,
    AutoLockSetting? autoLock,
    Profile? profile,
    bool clearProfile = false,
    bool? biometricEnabled,
  }) =>
      SessionState(
        status: status ?? this.status,
        discreet: discreet ?? this.discreet,
        autoLock: autoLock ?? this.autoLock,
        profile: clearProfile ? null : profile ?? this.profile,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      );
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

class SessionController extends Notifier<SessionState> {
  static const _kAutoLock = 'ft.settings.autoLock';
  static const _kBiometric = 'ft.settings.biometric';

  LocalStore? _store;
  DateTime? _backgroundedAt;

  /// Base de dados aberta; só existe enquanto o app está desbloqueado.
  LocalStore? get store => _store;

  @override
  SessionState build() {
    _init();
    return const SessionState(status: SessionStatus.loading);
  }

  Future<void> _init() async {
    final secrets = ref.read(secretStoreProvider);
    final hasPin = await ref.read(pinVaultProvider).hasPin();
    final savedLock = await secrets.read(_kAutoLock);
    final autoLock = AutoLockSetting.values
            .where((s) => s.name == savedLock)
            .firstOrNull ??
        AutoLockSetting.oneMinute;
    final biometric = hasPin && await secrets.read(_kBiometric) == '1';
    state = state.copyWith(
      status: hasPin ? SessionStatus.locked : SessionStatus.needsPin,
      autoLock: autoLock,
      biometricEnabled: biometric,
    );
  }

  Future<void> createPin(String pin) async {
    final factory = ref.read(localStoreFactoryProvider);
    // Um PIN novo implica uma chave nova: restos de dados antigos seriam
    // ilegíveis, por isso apagam-se antes.
    await factory.wipe();
    await ref.read(biometricKeyStoreProvider).clear();
    await ref.read(secretStoreProvider).delete(_kBiometric);
    state = state.copyWith(biometricEnabled: false);
    final key = await ref.read(pinVaultProvider).createPin(pin);
    await _openStore(key);
  }

  Future<UnlockResult> unlock(String pin) async {
    final result = await ref.read(pinVaultProvider).unlock(pin);
    if (result is UnlockSuccess) await _openStore(result.dataKey);
    return result;
  }

  /// Desbloqueia com a chave guardada sob biometria. O limite de tentativas
  /// do PIN continua a valer: atingido, a biometria deixa de servir.
  Future<BiometricResult> unlockWithBiometrics() async {
    if (!state.biometricEnabled) return const BiometricInvalidated();
    if ((await ref.read(pinVaultProvider).status()).signInRequired) {
      return const BiometricInvalidated();
    }
    final result = await ref.read(biometricKeyStoreProvider).load();
    switch (result) {
      case BiometricKey(:final dataKey):
        try {
          await _openStore(dataKey);
        } catch (_) {
          await disableBiometrics();
          return const BiometricInvalidated();
        }
      case BiometricInvalidated():
        await disableBiometrics();
      case BiometricCancelled():
        break;
    }
    return result;
  }

  /// Ativa a biometria. Pede o PIN outra vez: é ele que liberta a chave
  /// que fica guardada sob biometria.
  Future<BiometricSetup> enableBiometrics(String pin) async {
    final bio = ref.read(biometricKeyStoreProvider);
    if (!await bio.isAvailable()) return BiometricSetup.unavailable;
    final result = await ref.read(pinVaultProvider).unlock(pin);
    if (result is! UnlockSuccess) return BiometricSetup.wrongPin;
    final key = result.dataKey;
    try {
      await bio.save(key);
      await ref.read(secretStoreProvider).write(_kBiometric, '1');
      state = state.copyWith(biometricEnabled: true);
      return BiometricSetup.enabled;
    } catch (_) {
      return BiometricSetup.failed;
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<void> disableBiometrics() async {
    await ref.read(biometricKeyStoreProvider).clear();
    await ref.read(secretStoreProvider).delete(_kBiometric);
    state = state.copyWith(biometricEnabled: false);
  }

  Future<void> _openStore(Uint8List key) async {
    try {
      final store = await ref.read(localStoreFactoryProvider).open(key);
      final profile = await store.loadProfile();
      _store = store;
      state = state.copyWith(
        status: profile == null ? SessionStatus.onboarding : SessionStatus.unlocked,
        profile: profile,
      );
    } finally {
      // A chave só serve para abrir a base; não fica em memória.
      key.fillRange(0, key.length, 0);
    }
  }

  Future<void> completeOnboarding(Profile profile, Account firstAccount) async {
    final store = _store;
    if (store == null) throw StateError('App bloqueado');
    await store.completeOnboarding(profile, firstAccount);
    state = state.copyWith(status: SessionStatus.unlocked, profile: profile);
  }

  void lock() {
    final store = _store;
    _store = null;
    store?.close();
    if (state.status == SessionStatus.unlocked ||
        state.status == SessionStatus.onboarding) {
      state = state.copyWith(status: SessionStatus.locked, clearProfile: true);
    }
  }

  void onBackground() {
    _backgroundedAt ??= DateTime.now();
  }

  void onForeground() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || _store == null) return;
    if (AutoLockPolicy.shouldLock(
      backgroundedAt: since,
      now: DateTime.now(),
      setting: state.autoLock,
    )) {
      lock();
    }
  }

  void toggleDiscreet() {
    state = state.copyWith(discreet: !state.discreet);
  }

  Future<void> setAutoLock(AutoLockSetting setting) async {
    await ref.read(secretStoreProvider).write(_kAutoLock, setting.name);
    state = state.copyWith(autoLock: setting);
  }

  /// Apaga o PIN, a chave e a base de dados deste dispositivo.
  Future<void> resetApp() async {
    final store = _store;
    _store = null;
    await store?.close();
    await ref.read(localStoreFactoryProvider).wipe();
    await ref.read(pinVaultProvider).reset();
    await ref.read(secretStoreProvider).delete(_kAutoLock);
    await ref.read(biometricKeyStoreProvider).clear();
    await ref.read(secretStoreProvider).delete(_kBiometric);
    state = const SessionState(status: SessionStatus.needsPin);
  }
}

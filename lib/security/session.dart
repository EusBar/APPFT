import 'dart:typed_data';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/sqlcipher_store.dart';
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

enum SessionStatus { loading, needsPin, locked, onboarding, unlocked }

class SessionState {
  const SessionState({
    required this.status,
    this.discreet = false,
    this.autoLock = AutoLockSetting.oneMinute,
    this.profile,
  });

  final SessionStatus status;

  /// Modo discreto: todos os valores ficam ocultos.
  final bool discreet;

  /// Tempo em segundo plano até bloquear.
  final AutoLockSetting autoLock;

  /// Só existe com o app desbloqueado e o onboarding feito.
  final Profile? profile;

  SessionState copyWith({
    SessionStatus? status,
    bool? discreet,
    AutoLockSetting? autoLock,
    Profile? profile,
    bool clearProfile = false,
  }) =>
      SessionState(
        status: status ?? this.status,
        discreet: discreet ?? this.discreet,
        autoLock: autoLock ?? this.autoLock,
        profile: clearProfile ? null : profile ?? this.profile,
      );
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

class SessionController extends Notifier<SessionState> {
  static const _kAutoLock = 'ft.settings.autoLock';

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
    state = state.copyWith(
      status: hasPin ? SessionStatus.locked : SessionStatus.needsPin,
      autoLock: autoLock,
    );
  }

  Future<void> createPin(String pin) async {
    final factory = ref.read(localStoreFactoryProvider);
    // Um PIN novo implica uma chave nova: restos de dados antigos seriam
    // ilegíveis, por isso apagam-se antes.
    await factory.wipe();
    final key = await ref.read(pinVaultProvider).createPin(pin);
    await _openStore(key);
  }

  Future<UnlockResult> unlock(String pin) async {
    final result = await ref.read(pinVaultProvider).unlock(pin);
    if (result is UnlockSuccess) await _openStore(result.dataKey);
    return result;
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
    state = const SessionState(status: SessionStatus.needsPin);
  }
}

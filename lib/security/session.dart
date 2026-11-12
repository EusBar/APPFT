import 'dart:typed_data';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pin_vault.dart';
import 'secret_store.dart';

final secretStoreProvider = Provider<SecretStore>(
  (ref) => const KeystoreSecretStore(),
);

final pinVaultProvider = Provider<PinVault>(
  (ref) => PinVault(ref.watch(secretStoreProvider)),
);

enum SessionStatus { loading, needsPin, locked, unlocked }

class SessionState {
  const SessionState({required this.status, this.discreet = false});

  final SessionStatus status;

  /// Modo discreto: todos os valores ficam ocultos.
  final bool discreet;

  SessionState copyWith({SessionStatus? status, bool? discreet}) => SessionState(
        status: status ?? this.status,
        discreet: discreet ?? this.discreet,
      );
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

class SessionController extends Notifier<SessionState> {
  /// Tempo em segundo plano até bloquear. Passa a ser configurável nas
  /// Definições quando esse ecrã existir.
  static const autoLock = AutoLockSetting.oneMinute;

  Uint8List? _dataKey;
  DateTime? _backgroundedAt;

  /// Chave dos dados locais; só existe enquanto o app está desbloqueado.
  Uint8List? get dataKey => _dataKey;

  @override
  SessionState build() {
    _init();
    return const SessionState(status: SessionStatus.loading);
  }

  Future<void> _init() async {
    final hasPin = await ref.read(pinVaultProvider).hasPin();
    state = state.copyWith(
      status: hasPin ? SessionStatus.locked : SessionStatus.needsPin,
    );
  }

  Future<void> createPin(String pin) async {
    _dataKey = await ref.read(pinVaultProvider).createPin(pin);
    state = state.copyWith(status: SessionStatus.unlocked);
  }

  Future<UnlockResult> unlock(String pin) async {
    final result = await ref.read(pinVaultProvider).unlock(pin);
    if (result is UnlockSuccess) {
      _dataKey = result.dataKey;
      state = state.copyWith(status: SessionStatus.unlocked);
    }
    return result;
  }

  void lock() {
    _dataKey?.fillRange(0, _dataKey!.length, 0);
    _dataKey = null;
    if (state.status == SessionStatus.unlocked) {
      state = state.copyWith(status: SessionStatus.locked);
    }
  }

  void onBackground() {
    _backgroundedAt ??= DateTime.now();
  }

  void onForeground() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || state.status != SessionStatus.unlocked) return;
    if (AutoLockPolicy.shouldLock(
      backgroundedAt: since,
      now: DateTime.now(),
      setting: autoLock,
    )) {
      lock();
    }
  }

  void toggleDiscreet() {
    state = state.copyWith(discreet: !state.discreet);
  }

  /// Apaga o PIN e a chave de dados deste dispositivo.
  Future<void> resetApp() async {
    lock();
    await ref.read(pinVaultProvider).reset();
    state = const SessionState(status: SessionStatus.needsPin);
  }
}

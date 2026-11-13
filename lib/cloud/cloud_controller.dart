import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../finance/finance_data.dart';
import '../security/pin_vault.dart';
import '../security/session.dart';
import 'cloud_api.dart';
import 'cloud_crypto.dart';
import 'sync_engine.dart';

final cloudApiProvider = Provider<CloudApi>((ref) => HttpCloudApi());

/// Derivação de chaves da nuvem (Argon2id); trocada nos testes.
final cloudDeriverProvider = Provider<KeyDeriver>((ref) => deriveInIsolate);

class CloudState {
  const CloudState({
    this.loaded = false,
    this.email,
    this.lastSync,
    this.syncing = false,
    this.error,
  });

  final bool loaded;
  final String? email;
  final DateTime? lastSync;
  final bool syncing;
  final String? error;

  bool get signedIn => email != null;

  CloudState copyWith({
    bool? loaded,
    String? email,
    bool clearEmail = false,
    DateTime? lastSync,
    bool? syncing,
    String? error,
    bool clearError = false,
  }) =>
      CloudState(
        loaded: loaded ?? this.loaded,
        email: clearEmail ? null : email ?? this.email,
        lastSync: lastSync ?? this.lastSync,
        syncing: syncing ?? this.syncing,
        error: clearError ? null : error ?? this.error,
      );
}

/// A palavra-passe já não abre a chave (foi mudada noutro lado): é preciso
/// o código de recuperação.
class NeedsRecoveryCode implements Exception {
  const NeedsRecoveryCode();
}

/// Conta FINTRACK na nuvem. A sessão e a chave de dados ficam na base
/// cifrada do telemóvel (só acessíveis depois do desbloqueio).
class CloudController extends Notifier<CloudState> {
  static const _kEmail = 'cloud.email';
  static const _kRefresh = 'cloud.refresh';
  static const _kKey = 'cloud.key';
  static const _kLastSync = 'cloud.lastSync';

  Timer? _debounce;
  bool _applying = false;

  @override
  CloudState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const CloudState();
  }

  LocalStore? get _store => ref.read(sessionProvider.notifier).store;
  CloudApi get _api => ref.read(cloudApiProvider);

  /// Lê a sessão guardada (depois de desbloquear).
  Future<void> load() async {
    final store = _store;
    if (store == null) return;
    final email = await store.getSetting(_kEmail);
    final last = await store.getSetting(_kLastSync);
    state = CloudState(
      loaded: true,
      email: email,
      lastSync: last == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(last)),
    );
  }

  Future<void> _remember(LocalStore store, CloudSession s, Uint8List key) async {
    await store.setSetting(_kEmail, s.email);
    await store.setSetting(_kRefresh, s.refreshToken);
    await store.setSetting(_kKey, base64Encode(key));
    state = state.copyWith(email: s.email, loaded: true, clearError: true);
  }

  /// Cria a conta e a chave de dados. Devolve o código de recuperação, que o
  /// utilizador tem de guardar (não fica em lado nenhum).
  Future<String> signUp(String email, String password) async {
    final store = _store;
    if (store == null) throw StateError('App bloqueado');
    final session = await _api.signUp(email.trim(), password);
    final (code, key) = await _createVault(session, password);
    await _remember(store, session, key);
    return code;
  }

  Future<(String, Uint8List)> _createVault(CloudSession session, String password) async {
    final deriver = ref.read(cloudDeriverProvider);
    final key = CloudCrypto.newDataKey();
    final code = RecoveryCode.generate();
    await _api.putVault(
      session,
      RemoteVault(
        await KeyWrap.wrap(key, password, deriver: deriver),
        await KeyWrap.wrap(key, code, deriver: deriver),
      ),
      create: true,
    );
    return (code, key);
  }

  /// Entra numa conta existente. Se a palavra-passe não abrir a chave,
  /// lança [NeedsRecoveryCode]; repita com [recoveryCode]. Devolve um código
  /// novo se a conta ainda não tinha chave (criada sem cofre).
  Future<String?> signIn(String email, String password, {String? recoveryCode}) async {
    final store = _store;
    if (store == null) throw StateError('App bloqueado');
    final deriver = ref.read(cloudDeriverProvider);
    final session = await _api.signIn(email.trim(), password);
    final vault = await _api.getVault(session);
    if (vault == null) {
      final (code, key) = await _createVault(session, password);
      await _remember(store, session, key);
      return code;
    }
    Uint8List key;
    try {
      key = await KeyWrap.unwrap(vault.passwordWrap, password, deriver: deriver);
    } on FormatException {
      if (recoveryCode == null) throw const NeedsRecoveryCode();
      try {
        key = await KeyWrap.unwrap(vault.recoveryWrap, RecoveryCode.normalize(recoveryCode), deriver: deriver);
      } on FormatException {
        throw const CloudException('Código de recuperação errado.', code: 'bad_recovery');
      }
      // Volta a proteger a chave com a palavra-passe atual.
      await _api.putVault(
        session,
        RemoteVault(await KeyWrap.wrap(key, password, deriver: deriver), vault.recoveryWrap),
        create: false,
      );
    }
    await _remember(store, session, key);
    return null;
  }

  Future<CloudSession?> _session(LocalStore store) async {
    final refresh = await store.getSetting(_kRefresh);
    if (refresh == null) return null;
    final s = await _api.refresh(refresh);
    await store.setSetting(_kRefresh, s.refreshToken);
    return s;
  }

  /// Sincroniza agora. Devolve o relatório, ou `null` sem sessão.
  Future<SyncReport?> syncNow() async {
    final store = _store;
    if (store == null || state.syncing) return null;
    final keyB64 = await store.getSetting(_kKey);
    if (keyB64 == null) return null;
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final session = await _session(store);
      if (session == null) return null;
      final report = await SyncEngine(
        api: _api,
        store: store,
        crypto: CloudCrypto(base64Decode(keyB64)),
      ).run(session);
      final now = DateTime.now();
      await store.setSetting(_kLastSync, '${now.millisecondsSinceEpoch}');
      state = state.copyWith(lastSync: now, syncing: false);
      if (report.applied) {
        _applying = true;
        await ref.read(sessionProvider.notifier).reloadProfile();
        ref.invalidate(financeProvider);
      }
      return report;
    } on CloudException catch (e) {
      state = state.copyWith(syncing: false, error: e.message);
      return null;
    } catch (_) {
      state = state.copyWith(syncing: false, error: 'Não foi possível sincronizar.');
      return null;
    }
  }

  /// Depois de alterações locais: sincroniza passados uns segundos, uma vez.
  void scheduleSync() {
    if (!state.signedIn) return;
    if (_applying) {
      _applying = false; // a alteração veio da própria sincronização
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), syncNow);
  }

  /// Termina a sessão neste telemóvel. Os dados locais ficam.
  Future<void> signOut() async {
    final store = _store;
    if (store == null) return;
    try {
      final s = await _session(store);
      if (s != null) await _api.signOut(s);
    } catch (_) {
      // Sem rede: termina localmente na mesma.
    }
    await _forget(store);
  }

  /// Apaga a conta e todos os dados na nuvem. Os dados deste telemóvel ficam.
  Future<void> deleteCloudAccount() async {
    final store = _store;
    if (store == null) return;
    final s = await _session(store);
    if (s != null) await _api.deleteAccount(s);
    await _forget(store);
  }

  Future<void> _forget(LocalStore store) async {
    for (final k in [_kEmail, _kRefresh, _kKey, _kLastSync, SyncEngine.lastPullKey]) {
      await store.setSetting(k, null);
    }
    await store.saveSyncState({});
    state = const CloudState(loaded: true);
  }
}

final cloudProvider = NotifierProvider<CloudController, CloudState>(CloudController.new);

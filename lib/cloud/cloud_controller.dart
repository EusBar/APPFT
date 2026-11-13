import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../finance/finance_data.dart';
import '../notifications/reminders.dart';
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
    this.devices = const [],
    this.deviceId,
    this.newDevices = const [],
  });

  final bool loaded;
  final String? email;
  final DateTime? lastSync;
  final bool syncing;
  final String? error;
  final List<RemoteDevice> devices;

  /// Este telemóvel, na lista de dispositivos.
  final String? deviceId;

  /// Dispositivos que entraram na conta desde a última vez (aviso).
  final List<RemoteDevice> newDevices;

  bool get signedIn => email != null;

  CloudState copyWith({
    bool? loaded,
    String? email,
    DateTime? lastSync,
    bool? syncing,
    String? error,
    bool clearError = false,
    List<RemoteDevice>? devices,
    String? deviceId,
    List<RemoteDevice>? newDevices,
  }) =>
      CloudState(
        loaded: loaded ?? this.loaded,
        email: email ?? this.email,
        lastSync: lastSync ?? this.lastSync,
        syncing: syncing ?? this.syncing,
        error: clearError ? null : error ?? this.error,
        devices: devices ?? this.devices,
        deviceId: deviceId ?? this.deviceId,
        newDevices: newDevices ?? this.newDevices,
      );
}

/// A palavra-passe já não abre a chave (mudou noutro lado): é preciso o
/// código de recuperação. Repita com [CloudController.continueWithRecovery].
class NeedsRecoveryCode implements Exception {
  const NeedsRecoveryCode();
}

/// Passo seguinte depois de criar conta ou entrar.
sealed class CloudStep {
  const CloudStep();
}

/// Falta o código de 6 dígitos enviado por e-mail.
class NeedsEmailCode extends CloudStep {
  const NeedsEmailCode(this.email);
  final String email;
}

/// Sessão aberta. [recoveryCode] só vem quando foi criada uma chave nova
/// (tem de ser mostrado e guardado pelo utilizador).
class CloudReady extends CloudStep {
  const CloudReady({this.recoveryCode});
  final String? recoveryCode;
}

/// Conta FINTRACK na nuvem. A sessão e a chave de dados ficam na base
/// cifrada do telemóvel (só acessíveis depois do desbloqueio).
class CloudController extends Notifier<CloudState> {
  static const _kEmail = 'cloud.email';
  static const _kRefresh = 'cloud.refresh';
  static const _kKey = 'cloud.key';
  static const _kLastSync = 'cloud.lastSync';
  static const _kDeviceId = 'cloud.deviceId';
  static const _kDeviceName = 'cloud.deviceName';
  static const _kVerified = 'cloud.verifiedEmail';
  static const _kKnownDevices = 'cloud.knownDevices';

  Timer? _debounce;
  bool _applying = false;

  /// Muda a cada fim de sessão: resultados de pedidos antigos são ignorados.
  int _epoch = 0;

  // Fluxo em curso (só em memória, apagado no fim).
  String? _pendingEmail;
  String? _pendingPassword;
  bool _pendingSignUp = false;
  CloudSession? _pendingSession;

  @override
  CloudState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const CloudState();
  }

  LocalStore? get _store => ref.read(sessionProvider.notifier).store;
  CloudApi get _api => ref.read(cloudApiProvider);
  KeyDeriver get _deriver => ref.read(cloudDeriverProvider);

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
      deviceId: await store.getSetting(_kDeviceId),
    );
  }

  void _clearPending() {
    _pendingEmail = null;
    _pendingPassword = null;
    _pendingSession = null;
    _pendingSignUp = false;
  }

  // --- Criar conta e entrar ---------------------------------------------------

  Future<CloudStep> signUp(String email, String password) async {
    final e = email.trim().toLowerCase();
    final session = await _api.signUp(e, password);
    _pendingEmail = e;
    _pendingPassword = password;
    _pendingSignUp = true;
    if (session == null) return NeedsEmailCode(e);
    return _finish(session);
  }

  Future<CloudStep> signIn(String email, String password) async {
    final e = email.trim().toLowerCase();
    final session = await _api.signIn(e, password);
    _pendingEmail = e;
    _pendingPassword = password;
    _pendingSignUp = false;
    final store = _store;
    final verified = store == null ? null : await store.getSetting(_kVerified);
    if (await _api.emailConfirmationRequired() && verified != e) {
      // Dispositivo novo: prova de acesso ao e-mail antes de abrir os dados.
      await _api.sendLoginCode(e);
      return NeedsEmailCode(e);
    }
    return _finish(session);
  }

  /// Confirma o código de 6 dígitos recebido por e-mail.
  Future<CloudStep> confirmEmailCode(String code) async {
    final email = _pendingEmail;
    if (email == null) throw const CloudException('Recomece o início de sessão.');
    final session = await _api.verifyCode(email, code, type: _pendingSignUp ? 'signup' : 'email');
    await _store?.setSetting(_kVerified, email);
    return _finish(session);
  }

  /// Pede um novo código.
  Future<void> resendCode() async {
    final email = _pendingEmail;
    if (email == null) return;
    if (_pendingSignUp) {
      await _api.resendSignupCode(email);
    } else {
      await _api.sendLoginCode(email);
    }
  }

  /// Depois de [NeedsRecoveryCode]: abre a chave com o código de recuperação
  /// e volta a protegê-la com a palavra-passe atual.
  Future<CloudStep> continueWithRecovery(String recoveryCode) async {
    final session = _pendingSession;
    final password = _pendingPassword;
    if (session == null || password == null) throw const CloudException('Recomece o início de sessão.');
    final vault = await _api.getVault(session);
    if (vault == null) throw const CloudException('A conta não tem chave guardada.');
    Uint8List key;
    try {
      key = await KeyWrap.unwrap(vault.recoveryWrap, RecoveryCode.normalize(recoveryCode), deriver: _deriver);
    } on FormatException {
      throw const CloudException('Código de recuperação errado.', code: 'bad_recovery');
    }
    await _api.putVault(
      session,
      RemoteVault(await KeyWrap.wrap(key, password, deriver: _deriver), vault.recoveryWrap),
      create: false,
    );
    await _remember(session, key);
    return const CloudReady();
  }

  Future<CloudStep> _finish(CloudSession session) async {
    final password = _pendingPassword!;
    _pendingSession = session;
    final vault = await _api.getVault(session);
    if (vault == null) {
      final key = CloudCrypto.newDataKey();
      final code = RecoveryCode.generate();
      await _api.putVault(
        session,
        RemoteVault(
          await KeyWrap.wrap(key, password, deriver: _deriver),
          await KeyWrap.wrap(key, code, deriver: _deriver),
        ),
        create: true,
      );
      await _remember(session, key);
      return CloudReady(recoveryCode: code);
    }
    Uint8List key;
    try {
      key = await KeyWrap.unwrap(vault.passwordWrap, password, deriver: _deriver);
    } on FormatException {
      throw const NeedsRecoveryCode();
    }
    await _remember(session, key);
    return const CloudReady();
  }

  /// Sessão aberta antes de existir PIN (primeira abertura): fica só em
  /// memória até a base cifrada ser criada.
  (CloudSession, Uint8List, String)? _parked;

  /// Depois de criar o PIN: guarda a sessão estacionada e traz os dados.
  Future<void> adoptParked() async {
    final parked = _parked;
    if (parked == null) return;
    _parked = null;
    final (session, key, email) = parked;
    _pendingEmail = email;
    await _remember(session, key);
    await syncNow();
  }

  Future<void> _remember(CloudSession s, Uint8List key) async {
    final store = _store;
    if (store == null) {
      _parked = (s, key, s.email.isEmpty ? _pendingEmail! : s.email);
      _clearPending();
      return;
    }
    await store.setSetting(_kEmail, s.email.isEmpty ? _pendingEmail : s.email);
    await store.setSetting(_kRefresh, s.refreshToken);
    await store.setSetting(_kKey, base64Encode(key));
    await store.setSetting(_kVerified, s.email.isEmpty ? _pendingEmail : s.email);
    state = state.copyWith(email: s.email.isEmpty ? _pendingEmail : s.email, loaded: true, clearError: true);
    _clearPending();
  }

  // --- Sessão e sincronização --------------------------------------------------

  static const _endedCodes = {'session_not_found', 'refresh_token_not_found', 'invalid_grant', 'unauthorized'};

  Future<CloudSession?> _session(LocalStore store) async {
    final epoch = _epoch;
    final refresh = await store.getSetting(_kRefresh);
    if (refresh == null) return null;
    try {
      final s = await _api.refresh(refresh);
      if (epoch != _epoch) {
        // A sessão foi terminada enquanto o pedido estava em curso.
        unawaited(_api.signOut(s).catchError((_) {}));
        return null;
      }
      await store.setSetting(_kRefresh, s.refreshToken);
      return s;
    } on CloudException catch (e) {
      if (epoch != _epoch) return null;
      if (_endedCodes.contains(e.code)) {
        // Sessão terminada noutro dispositivo: sai daqui (os dados ficam).
        await _forget(store);
        state = state.copyWith(error: 'A sessão terminou. Entre de novo para continuar a sincronizar.');
        return null;
      }
      rethrow;
    }
  }

  /// Sincroniza agora. Devolve o relatório, ou `null` sem sessão.
  Future<SyncReport?> syncNow() async {
    final store = _store;
    if (store == null || state.syncing) return null;
    final keyB64 = await store.getSetting(_kKey);
    if (keyB64 == null) return null;
    final epoch = _epoch;
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final session = await _session(store);
      if (session == null) {
        state = state.copyWith(syncing: false);
        return null;
      }
      final report = await SyncEngine(
        api: _api,
        store: store,
        crypto: CloudCrypto(base64Decode(keyB64)),
      ).run(session);
      if (epoch != _epoch) return null; // sessão terminada entretanto
      await _touchDevice(store, session);
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
      if (epoch != _epoch) return null;
      state = state.copyWith(syncing: false, error: e.message);
      return null;
    } catch (_) {
      if (epoch != _epoch) return null;
      state = state.copyWith(syncing: false, error: 'Não foi possível sincronizar.');
      return null;
    }
  }

  /// Sincroniza se a última vez já foi há mais de [age] (ao voltar ao app).
  Future<void> syncIfStale([Duration age = const Duration(minutes: 2)]) async {
    if (!state.signedIn) return;
    final last = state.lastSync;
    if (last != null && DateTime.now().difference(last) < age) return;
    await syncNow();
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

  // --- Dispositivos -------------------------------------------------------------

  static String get _platform => Platform.isAndroid
      ? 'android'
      : Platform.isIOS
          ? 'ios'
          : 'other';

  static String _defaultName() {
    final now = DateTime.now();
    final base = switch (_platform) { 'android' => 'Android', 'ios' => 'iPhone', _ => 'Dispositivo' };
    return '$base · ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  Future<void> _touchDevice(LocalStore store, CloudSession session) async {
    var id = await store.getSetting(_kDeviceId);
    if (id == null) {
      id = base64UrlEncode(CloudCrypto.newDataKey().sublist(0, 12));
      await store.setSetting(_kDeviceId, id);
    }
    var name = await store.getSetting(_kDeviceName);
    if (name == null) {
      name = _defaultName();
      await store.setSetting(_kDeviceName, name);
    }
    await _api.upsertDevice(session, id: id, name: name, platform: _platform);
    final list = await _api.devices(session);
    final knownRaw = await store.getSetting(_kKnownDevices);
    final known = knownRaw == null ? null : {for (final x in jsonDecode(knownRaw) as List<Object?>) x! as String};
    final fresh = known == null ? <RemoteDevice>[] : [for (final d in list) if (d.id != id && !known.contains(d.id)) d];
    await store.setSetting(_kKnownDevices, jsonEncode([for (final d in list) d.id]));
    state = state.copyWith(devices: list, deviceId: id, newDevices: [...state.newDevices, ...fresh]);
  }

  /// O utilizador viu o aviso de novos dispositivos.
  void acknowledgeNewDevices() => state = state.copyWith(newDevices: const []);

  Future<void> renameDevice(String name) async {
    final store = _store;
    final clean = name.trim();
    if (store == null || clean.isEmpty || clean.length > 60) return;
    await store.setSetting(_kDeviceName, clean);
    final s = await _session(store);
    if (s != null) await _touchDevice(store, s);
  }

  /// Termina a sessão em todos os outros dispositivos.
  Future<void> signOutOtherDevices() async {
    final store = _store;
    if (store == null) return;
    final s = await _session(store);
    if (s == null) return;
    await _api.signOutOthers(s);
    final me = state.deviceId;
    for (final d in state.devices) {
      if (d.id != me) await _api.deleteDevice(s, d.id);
    }
    await _touchDevice(store, s);
  }

  /// Termina a sessão neste telemóvel. Os dados locais ficam.
  /// Última sincronização antes de sair. `false` se não foi possível (sem
  /// rede): alterações recentes ainda não estão na nuvem.
  Future<bool> flushBeforeSignOut() async {
    while (state.syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return await syncNow() != null;
  }

  /// Termina a sessão: os dados da conta saem deste telemóvel e o app volta
  /// ao ecrã de entrada. O aviso ao servidor segue em fundo.
  Future<void> signOut() async {
    final store = _store;
    if (store == null) return;
    final refresh = await store.getSetting(_kRefresh);
    final id = state.deviceId;
    // Identidade do aparelho: continua a ser o mesmo telemóvel.
    final keep = {
      for (final k in [_kDeviceId, _kDeviceName, _kVerified]) k: await store.getSetting(k),
    };
    await _forget(store);
    if (refresh != null) unawaited(_remoteSignOut(refresh, id));
    try {
      await ref.read(remindersProvider).cancelAll();
    } catch (_) {
      // Sem permissão de notificações: nada agendado.
    }
    await ref.read(sessionProvider.notifier).clearAfterSignOut();
    for (final e in keep.entries) {
      if (e.value != null) await store.setSetting(e.key, e.value);
    }
    ref.invalidate(financeProvider);
  }

  Future<void> _remoteSignOut(String refresh, String? deviceId) async {
    try {
      final s = await _api.refresh(refresh);
      if (deviceId != null) await _api.deleteDevice(s, deviceId);
      await _api.signOut(s);
    } catch (_) {
      // Sem rede ou token já trocado: a sessão local já terminou.
    }
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
    _epoch++;
    _debounce?.cancel();
    for (final k in [_kEmail, _kRefresh, _kKey, _kLastSync, _kKnownDevices, SyncEngine.lastPullKey]) {
      await store.setSetting(k, null);
    }
    await store.saveSyncState({});
    state = CloudState(loaded: true, deviceId: state.deviceId);
  }
}

final cloudProvider = NotifierProvider<CloudController, CloudState>(CloudController.new);

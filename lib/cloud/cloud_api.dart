import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'cloud_config.dart';

/// Erro da nuvem já em português, pronto a mostrar.
class CloudException implements Exception {
  const CloudException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => message;
}

class CloudSession {
  const CloudSession({
    required this.userId,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
  });

  final String userId;
  final String email;
  final String accessToken;
  final String refreshToken;
}

/// Registo tal como está no servidor: só texto cifrado.
class RemoteRecord {
  const RemoteRecord({
    required this.kind,
    required this.id,
    required this.payload,
    this.deleted = false,
    this.updatedAt,
  });

  final String kind;
  final String id;
  final String payload;
  final bool deleted;
  final DateTime? updatedAt;
}

class RemoteDevice {
  const RemoteDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.createdAt,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final String platform;
  final DateTime createdAt;
  final DateTime lastSeen;
}

class RemoteVault {
  const RemoteVault(this.passwordWrap, this.recoveryWrap);
  final String passwordWrap;
  final String recoveryWrap;
}

abstract interface class CloudApi {
  /// O servidor exige confirmar o e-mail (e código em dispositivos novos)?
  Future<bool> emailConfirmationRequired();

  /// Devolve `null` quando a conta fica à espera do código de confirmação.
  Future<CloudSession?> signUp(String email, String password);

  /// Confirma um código de 6 dígitos ([type]: 'signup' ou 'email').
  Future<CloudSession> verifyCode(String email, String code, {required String type});

  /// Envia por e-mail um código para entrar (dispositivo novo).
  Future<void> sendLoginCode(String email);

  /// Volta a enviar o código de confirmação da conta.
  Future<void> resendSignupCode(String email);

  /// Termina as sessões dos outros dispositivos.
  Future<void> signOutOthers(CloudSession session);

  Future<void> upsertDevice(CloudSession session, {required String id, required String name, required String platform});
  Future<List<RemoteDevice>> devices(CloudSession session);
  Future<void> deleteDevice(CloudSession session, String id);
  Future<CloudSession> signIn(String email, String password);
  Future<CloudSession> refresh(String refreshToken);
  Future<void> signOut(CloudSession session);
  Future<RemoteVault?> getVault(CloudSession session);
  Future<void> putVault(CloudSession session, RemoteVault vault, {required bool create});
  Future<List<RemoteRecord>> pull(CloudSession session, {DateTime? since});
  Future<void> push(CloudSession session, List<RemoteRecord> records);
  Future<void> deleteAccount(CloudSession session);
}

/// Cliente HTTP direto para o Supabase (Auth + REST), sem SDK pesado.
class HttpCloudApi implements CloudApi {
  HttpCloudApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 20);

  Map<String, String> _headers([CloudSession? s]) => {
        'apikey': CloudConfig.publishableKey,
        'Content-Type': 'application/json',
        if (s != null) 'Authorization': 'Bearer ${s.accessToken}',
      };

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('${CloudConfig.url}$path').replace(queryParameters: query);

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw const CloudException('A ligação demorou demasiado. Tente de novo.', code: 'timeout');
    } on CloudException {
      rethrow;
    } on SocketException {
      throw const CloudException('Sem ligação à Internet.', code: 'offline');
    } on http.ClientException catch (e) {
      throw CloudException('Sem ligação ao servidor (${e.message}).', code: 'offline');
    } on HandshakeException {
      throw const CloudException('Ligação segura recusada. Verifique a data e hora do telemóvel.', code: 'tls');
    } catch (e) {
      throw CloudException('Erro inesperado na ligação (${e.runtimeType}).', code: 'unknown');
    }
  }

  static CloudException _authError(http.Response r) {
    String code = '';
    String msg = '';
    try {
      final j = jsonDecode(r.body) as Map<String, Object?>;
      code = (j['error_code'] ?? j['code'] ?? j['error'] ?? '').toString();
      msg = (j['msg'] ?? j['message'] ?? j['error_description'] ?? '').toString();
    } catch (_) {}
    final m = switch (code) {
      'invalid_credentials' || 'invalid_grant' => 'E-mail ou palavra-passe errados.',
      'user_already_exists' || 'email_exists' => 'Já existe uma conta com este e-mail. Entre em vez de criar.',
      'weak_password' => 'Palavra-passe fraca: use pelo menos 10 caracteres, com maiúsculas, minúsculas e algarismos.',
      'email_address_invalid' || 'validation_failed' => 'E-mail inválido.',
      'over_request_rate_limit' || 'over_email_send_rate_limit' => 'Demasiadas tentativas. Espere alguns minutos.',
      'refresh_token_not_found' || 'session_not_found' => 'A sessão terminou. Entre de novo.',
      'otp_expired' => 'Código errado ou expirado. Peça um novo.',
      'email_not_confirmed' => 'Falta confirmar o e-mail com o código enviado.',
      _ => msg.isNotEmpty ? 'Não foi possível concluir: $msg' : 'Não foi possível concluir (erro ${r.statusCode}).',
    };
    return CloudException(m, code: code);
  }

  CloudSession _session(http.Response r) {
    if (r.statusCode >= 400) throw _authError(r);
    final j = jsonDecode(r.body) as Map<String, Object?>;
    final user = j['user'] as Map<String, Object?>?;
    final access = j['access_token'] as String?;
    final refresh = j['refresh_token'] as String?;
    if (user == null || access == null || refresh == null) {
      throw const CloudException('Conta criada, mas falta confirmar o e-mail.', code: 'email_not_confirmed');
    }
    return CloudSession(
      userId: user['id']! as String,
      email: (user['email'] as String?) ?? '',
      accessToken: access,
      refreshToken: refresh,
    );
  }

  bool? _confirmation;

  @override
  Future<bool> emailConfirmationRequired() async {
    final cached = _confirmation;
    if (cached != null) return cached;
    final r = await _send(() => _client.get(_u('/auth/v1/settings'), headers: _headers()));
    if (r.statusCode >= 400) return false;
    final j = jsonDecode(r.body) as Map<String, Object?>;
    return _confirmation = j['mailer_autoconfirm'] != true;
  }

  @override
  Future<CloudSession?> signUp(String email, String password) async {
    final r = await _send(() => _client.post(
          _u('/auth/v1/signup'),
          headers: _headers(),
          body: jsonEncode({'email': email, 'password': password}),
        ));
    if (r.statusCode >= 400) throw _authError(r);
    final j = jsonDecode(r.body) as Map<String, Object?>;
    if (j['access_token'] == null) return null; // à espera do código
    return _session(r);
  }

  @override
  Future<CloudSession> verifyCode(String email, String code, {required String type}) async {
    final r = await _send(() => _client.post(
          _u('/auth/v1/verify'),
          headers: _headers(),
          body: jsonEncode({'type': type, 'email': email, 'token': code.trim()}),
        ));
    if (r.statusCode >= 400) {
      final e = _authError(r);
      if (e.code == 'otp_expired' || e.code == 'otp_disabled' || r.statusCode == 403) {
        throw const CloudException('Código errado ou expirado. Peça um novo.', code: 'otp');
      }
      throw e;
    }
    return _session(r);
  }

  @override
  Future<void> sendLoginCode(String email) async {
    final r = await _send(() => _client.post(
          _u('/auth/v1/otp'),
          headers: _headers(),
          body: jsonEncode({'email': email, 'create_user': false}),
        ));
    if (r.statusCode >= 400) throw _authError(r);
  }

  @override
  Future<void> resendSignupCode(String email) async {
    final r = await _send(() => _client.post(
          _u('/auth/v1/resend'),
          headers: _headers(),
          body: jsonEncode({'type': 'signup', 'email': email}),
        ));
    if (r.statusCode >= 400) throw _authError(r);
  }

  @override
  Future<void> signOutOthers(CloudSession session) async {
    final r = await _send(() => _client.post(_u('/auth/v1/logout', {'scope': 'others'}), headers: _headers(session)));
    if (r.statusCode >= 400) throw _authError(r);
  }

  @override
  Future<void> upsertDevice(CloudSession session, {required String id, required String name, required String platform}) async {
    final r = await _send(() => _client.post(
          _u('/rest/v1/devices', {'on_conflict': 'user_id,id'}),
          headers: {..._headers(session), 'Prefer': 'resolution=merge-duplicates,return=minimal'},
          body: jsonEncode({'id': id, 'name': name, 'platform': platform}),
        ));
    _check(r);
  }

  @override
  Future<List<RemoteDevice>> devices(CloudSession session) async {
    final r = await _send(() => _client.get(
          _u('/rest/v1/devices', {'select': 'id,name,platform,created_at,last_seen', 'order': 'last_seen.desc'}),
          headers: _headers(session),
        ));
    _check(r);
    return [
      for (final row in jsonDecode(r.body) as List<Object?>)
        RemoteDevice(
          id: (row! as Map<String, Object?>)['id']! as String,
          name: row['name']! as String,
          platform: row['platform']! as String,
          createdAt: DateTime.parse(row['created_at']! as String),
          lastSeen: DateTime.parse(row['last_seen']! as String),
        ),
    ];
  }

  @override
  Future<void> deleteDevice(CloudSession session, String id) async {
    final r = await _send(() => _client.delete(_u('/rest/v1/devices', {'id': 'eq.$id'}), headers: _headers(session)));
    _check(r);
  }

  @override
  Future<CloudSession> signIn(String email, String password) async => _session(await _send(() => _client.post(
        _u('/auth/v1/token', {'grant_type': 'password'}),
        headers: _headers(),
        body: jsonEncode({'email': email, 'password': password}),
      )));

  @override
  Future<CloudSession> refresh(String refreshToken) async => _session(await _send(() => _client.post(
        _u('/auth/v1/token', {'grant_type': 'refresh_token'}),
        headers: _headers(),
        body: jsonEncode({'refresh_token': refreshToken}),
      )));

  @override
  Future<void> signOut(CloudSession session) async {
    await _send(() => _client.post(_u('/auth/v1/logout'), headers: _headers(session)));
  }

  void _check(http.Response r) {
    if (r.statusCode >= 400) {
      if (r.statusCode == 401) throw const CloudException('A sessão terminou. Entre de novo.', code: 'unauthorized');
      throw CloudException('A nuvem recusou o pedido (erro ${r.statusCode}).', code: '${r.statusCode}');
    }
  }

  @override
  Future<RemoteVault?> getVault(CloudSession session) async {
    final r = await _send(() => _client.get(
          _u('/rest/v1/vaults', {'select': 'password_wrap,recovery_wrap'}),
          headers: _headers(session),
        ));
    _check(r);
    final rows = jsonDecode(r.body) as List<Object?>;
    if (rows.isEmpty) return null;
    final row = rows.first! as Map<String, Object?>;
    return RemoteVault(row['password_wrap']! as String, row['recovery_wrap']! as String);
  }

  @override
  Future<void> putVault(CloudSession session, RemoteVault vault, {required bool create}) async {
    final body = jsonEncode({'password_wrap': vault.passwordWrap, 'recovery_wrap': vault.recoveryWrap});
    final r = create
        ? await _send(() => _client.post(_u('/rest/v1/vaults'), headers: _headers(session), body: body))
        : await _send(() => _client.patch(
              _u('/rest/v1/vaults', {'user_id': 'eq.${session.userId}'}),
              headers: _headers(session),
              body: body,
            ));
    _check(r);
  }

  @override
  Future<List<RemoteRecord>> pull(CloudSession session, {DateTime? since}) async {
    const page = 1000;
    final out = <RemoteRecord>[];
    for (var offset = 0;; offset += page) {
      final r = await _send(() => _client.get(
            _u('/rest/v1/records', {
              'select': 'kind,id,payload,deleted,updated_at',
              if (since != null) 'updated_at': 'gte.${since.toUtc().toIso8601String()}',
              'order': 'updated_at.asc,kind.asc,id.asc',
              'limit': '$page',
              'offset': '$offset',
            }),
            headers: _headers(session),
          ));
      _check(r);
      final rows = jsonDecode(r.body) as List<Object?>;
      for (final row in rows) {
        final m = row! as Map<String, Object?>;
        out.add(RemoteRecord(
          kind: m['kind']! as String,
          id: m['id']! as String,
          payload: m['payload']! as String,
          deleted: m['deleted'] == true,
          updatedAt: DateTime.parse(m['updated_at']! as String),
        ));
      }
      if (rows.length < page) break;
    }
    return out;
  }

  @override
  Future<void> push(CloudSession session, List<RemoteRecord> records) async {
    Future<void> send(List<RemoteRecord> batch, String resolution) async {
      for (var i = 0; i < batch.length; i += 200) {
        final chunk = batch.sublist(i, i + 200 > batch.length ? batch.length : i + 200);
        final r = await _send(() => _client.post(
              _u('/rest/v1/records', {'on_conflict': 'user_id,kind,id'}),
              headers: {..._headers(session), 'Prefer': 'resolution=$resolution,return=minimal'},
              body: jsonEncode([
                for (final x in chunk) {'kind': x.kind, 'id': x.id, 'payload': x.payload, 'deleted': x.deleted},
              ]),
            ));
        _check(r);
      }
    }

    // Movimentos só se acrescentam: duplicados são ignorados, nunca alterados.
    await send([for (final r in records) if (r.kind == 'movement') r], 'ignore-duplicates');
    await send([for (final r in records) if (r.kind != 'movement') r], 'merge-duplicates');
  }

  @override
  Future<void> deleteAccount(CloudSession session) async {
    final r = await _send(() => _client.post(
          _u('/rest/v1/rpc/delete_my_account'),
          headers: _headers(session),
          body: '{}',
        ));
    _check(r);
  }
}

/// Nuvem em memória para testes: aplica as mesmas regras do servidor
/// (isolamento por utilizador, movimentos só acrescentam).
@visibleForTesting
class MemoryCloudApi implements CloudApi {
  final Map<String, (String id, String password)> users = {};
  final Map<String, RemoteVault> vaults = {};
  final Map<String, Map<String, RemoteRecord>> records = {};
  int _clock = 0;
  bool offline = false;
  bool confirmation = false;
  final Set<String> unconfirmed = {};
  final Map<String, String> sentCodes = {};
  final Map<String, Map<String, RemoteDevice>> deviceRows = {};
  int signedOutOthers = 0;

  @override
  Future<bool> emailConfirmationRequired() async => confirmation;

  @override
  Future<CloudSession> verifyCode(String email, String code, {required String type}) async {
    _net();
    if (sentCodes[email] != code) throw const CloudException('Código errado ou expirado. Peça um novo.', code: 'otp');
    sentCodes.remove(email);
    unconfirmed.remove(email);
    return _s(email);
  }

  @override
  Future<void> sendLoginCode(String email) async {
    _net();
    if (!users.containsKey(email)) throw const CloudException('Conta desconhecida.', code: 'user_not_found');
    sentCodes[email] = '654321';
  }

  @override
  Future<void> resendSignupCode(String email) async => sentCodes[email] = '123456';

  @override
  Future<void> signOutOthers(CloudSession session) async => signedOutOthers++;

  @override
  Future<void> upsertDevice(CloudSession s, {required String id, required String name, required String platform}) async {
    _net();
    final mine = deviceRows.putIfAbsent(s.userId, () => {});
    final now = DateTime.utc(2026).add(Duration(seconds: ++_clock));
    mine[id] = RemoteDevice(
      id: id,
      name: name,
      platform: platform,
      createdAt: mine[id]?.createdAt ?? now,
      lastSeen: now,
    );
  }

  @override
  Future<List<RemoteDevice>> devices(CloudSession s) async => [...?deviceRows[s.userId]?.values];

  @override
  Future<void> deleteDevice(CloudSession s, String id) async => deviceRows[s.userId]?.remove(id);

  CloudSession _s(String email) {
    final u = users[email]!;
    return CloudSession(userId: u.$1, email: email, accessToken: 'a-${u.$1}', refreshToken: 'r-${u.$1}');
  }

  void _net() {
    if (offline) throw const CloudException('Sem ligação à Internet.', code: 'offline');
  }

  @override
  Future<CloudSession?> signUp(String email, String password) async {
    _net();
    if (users.containsKey(email)) throw const CloudException('Já existe uma conta com este e-mail.', code: 'user_already_exists');
    users[email] = ('user-${users.length + 1}', password);
    if (confirmation) {
      unconfirmed.add(email);
      sentCodes[email] = '123456';
      return null;
    }
    return _s(email);
  }

  @override
  Future<CloudSession> signIn(String email, String password) async {
    _net();
    final u = users[email];
    if (u == null || u.$2 != password) throw const CloudException('E-mail ou palavra-passe errados.', code: 'invalid_credentials');
    if (unconfirmed.contains(email)) {
      throw const CloudException('Falta confirmar o e-mail com o código enviado.', code: 'email_not_confirmed');
    }
    return _s(email);
  }

  @override
  Future<CloudSession> refresh(String refreshToken) async {
    _net();
    final e = users.entries.firstWhere((e) => 'r-${e.value.$1}' == refreshToken,
        orElse: () => throw const CloudException('A sessão terminou.', code: 'session_not_found'));
    return _s(e.key);
  }

  @override
  Future<void> signOut(CloudSession session) async {}

  @override
  Future<RemoteVault?> getVault(CloudSession s) async {
    _net();
    return vaults[s.userId];
  }

  @override
  Future<void> putVault(CloudSession s, RemoteVault vault, {required bool create}) async {
    _net();
    if (create && vaults.containsKey(s.userId)) throw const CloudException('Já existe', code: '409');
    vaults[s.userId] = vault;
  }

  @override
  Future<List<RemoteRecord>> pull(CloudSession s, {DateTime? since}) async {
    _net();
    final all = records[s.userId]?.values ?? const <RemoteRecord>[];
    return [
      for (final r in all)
        if (since == null || !r.updatedAt!.isBefore(since)) r,
    ]..sort((a, b) => a.updatedAt!.compareTo(b.updatedAt!));
  }

  @override
  Future<void> push(CloudSession s, List<RemoteRecord> list) async {
    _net();
    final mine = records.putIfAbsent(s.userId, () => {});
    for (final r in list) {
      final key = '${r.kind}/${r.id}';
      if (r.kind == 'movement' && mine.containsKey(key)) continue;
      mine[key] = RemoteRecord(
        kind: r.kind,
        id: r.id,
        payload: r.payload,
        deleted: r.deleted,
        updatedAt: DateTime.utc(2026).add(Duration(seconds: ++_clock)),
      );
    }
  }

  @override
  Future<void> deleteAccount(CloudSession s) async {
    records.remove(s.userId);
    vaults.remove(s.userId);
    users.removeWhere((_, u) => u.$1 == s.userId);
  }
}

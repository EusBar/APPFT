import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../data/local_store.dart';
import '../data/snapshot.dart';
import 'cloud_api.dart';
import 'cloud_crypto.dart';

/// Tipos de registo sincronizados e a lista correspondente no Snapshot.
const _lists = {
  'account': 'accounts',
  'category': 'categories',
  'movement': 'movements',
  'commitment': 'commitments',
  'budget': 'budgets',
  'goal': 'goals',
  'goal_contribution': 'goalContributions',
  'kixikila': 'kixikilas',
  'kixikila_record': 'kixikilaRecords',
};

class SyncReport {
  const SyncReport({required this.pulled, required this.pushed, required this.applied});

  /// Registos recebidos da nuvem que mudaram algo neste telemóvel.
  final int pulled;

  /// Registos enviados.
  final int pushed;

  /// Os dados locais foram substituídos pela fusão.
  final bool applied;
}

/// Sincronização offline-first:
/// - o telemóvel é a fonte principal; a nuvem guarda só texto cifrado;
/// - cada registo tem um resumo (SHA-256) do último estado sincronizado,
///   para saber o que mudou de cada lado;
/// - movimentos nunca entram em conflito (só se acrescentam);
/// - nas definições (contas, orçamentos, ...), se os dois lados mudaram,
///   vence este telemóvel, e a nuvem fica com a versão dele.
class SyncEngine {
  SyncEngine({required this.api, required this.store, required this.crypto});

  final CloudApi api;
  final LocalStore store;
  final CloudCrypto crypto;

  static const lastPullKey = 'cloud.lastPull';

  static final _sha = Sha256();

  static Future<String> _hash(String json) async =>
      base64Encode((await _sha.hash(utf8.encode(json))).bytes);

  /// Registos locais: "tipo/id" -> JSON.
  static Map<String, String> _flatten(Map<String, Object?>? snapshot) {
    final out = <String, String>{};
    if (snapshot == null) return out;
    out['profile/me'] = jsonEncode(snapshot['profile']);
    _lists.forEach((kind, list) {
      for (final item in (snapshot[list] as List<Object?>? ?? const [])) {
        final m = item! as Map<String, Object?>;
        out['$kind/${m['id']}'] = jsonEncode(m);
      }
    });
    return out;
  }

  static Map<String, Object?> _rebuild(Map<String, String> records) {
    final lists = {for (final l in _lists.values) l: <Map<String, Object?>>[]};
    Map<String, Object?>? profile;
    records.forEach((key, json) {
      final kind = key.substring(0, key.indexOf('/'));
      final value = jsonDecode(json) as Map<String, Object?>;
      if (kind == 'profile') {
        profile = value;
      } else {
        final list = _lists[kind];
        if (list != null) lists[list]!.add(value);
      }
    });
    // Ordem que respeita as referências: originais antes dos estornos.
    // Ordenação estável (empates mantêm a ordem); as outras listas ficam
    // pela ordem em que estavam.
    final moves = lists['movements']!;
    final indexed = [for (final (i, m) in moves.indexed) (i, m)]
      ..sort((a, b) {
        final c = (a.$2['createdAt']! as int).compareTo(b.$2['createdAt']! as int);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    lists['movements'] = [for (final x in indexed) x.$2];
    return {
      'format': Snapshot.format,
      'version': Snapshot.version,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'profile': profile,
      ...lists,
    };
  }

  Future<SyncReport> run(CloudSession session) async {
    // 1. Estado local atual.
    final profile = await store.loadProfile();
    final localJson = profile == null ? null : (await Snapshot.read(store)).toJson();
    final local = _flatten(localJson);
    final localHash = {for (final e in local.entries) e.key: await _hash(e.value)};
    final synced = await store.syncState();

    // 2. O que mudou na nuvem desde a última vez.
    final lastPullRaw = await store.getSetting(lastPullKey);
    final since = lastPullRaw == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(lastPullRaw), isUtc: true);
    final remote = await api.pull(session, since: since);
    DateTime? newest;

    // Primeira sincronização deste telemóvel: em conflito, vence a nuvem
    // (o onboarding rápido de um telemóvel novo não apaga o perfil real).
    final firstSync = synced.isEmpty;
    final merged = Map.of(local);
    final newSynced = Map.of(synced);
    final toPush = <String>{};
    var pulled = 0;

    for (final r in remote) {
      if (r.updatedAt != null && (newest == null || r.updatedAt!.isAfter(newest))) newest = r.updatedAt;
      final key = '${r.kind}/${r.id}';
      final known = synced[key];
      final mine = localHash[key];
      final changedHere = mine != known; // inclui criado ou apagado aqui
      if (r.deleted) {
        if (!changedHere && local.containsKey(key)) {
          merged.remove(key);
          newSynced.remove(key);
          pulled++;
        } else if (!local.containsKey(key)) {
          newSynced.remove(key);
        }
        continue;
      }
      final json = await crypto.open(r.kind, r.id, r.payload);
      final theirs = await _hash(json);
      if (theirs == mine) {
        newSynced[key] = theirs; // já iguais
        continue;
      }
      if (!changedHere || firstSync) {
        // Só mudou na nuvem (ou é novo, ou primeira vez): fica a da nuvem.
        merged[key] = json;
        newSynced[key] = theirs;
        pulled++;
      } else if (mine == null && r.kind != 'movement') {
        // Apagado aqui, alterado lá: vence o apagar deste telemóvel.
        toPush.add(key);
      } else {
        // Os dois lados mudaram: vence este telemóvel.
        toPush.add(key);
      }
    }

    // 3. O que mudou aqui e ainda não foi enviado.
    for (final key in local.keys) {
      if (localHash[key] != newSynced[key] && merged[key] == local[key]) toPush.add(key);
    }
    final deletedHere = [
      for (final key in synced.keys)
        if (!local.containsKey(key) && merged.containsKey(key) == false && !key.startsWith('movement/')) key,
    ];

    // 4. Aplicar a fusão neste telemóvel (só se veio algo da nuvem).
    var applied = false;
    if (pulled > 0) {
      final snapshotJson = _rebuild(merged);
      if (snapshotJson['profile'] == null) {
        throw const CloudException('A conta na nuvem ainda não tem dados para trazer.', code: 'empty');
      }
      final snapshot = Snapshot.fromJson(snapshotJson)..validate();
      await store.replaceAll(snapshot);
      applied = true;
    }

    // 5. Enviar, cifrado.
    final outgoing = <RemoteRecord>[];
    for (final key in toPush) {
      final json = merged[key];
      if (json == null) continue;
      final slash = key.indexOf('/');
      final kind = key.substring(0, slash);
      final id = key.substring(slash + 1);
      outgoing.add(RemoteRecord(kind: kind, id: id, payload: await crypto.seal(kind, id, json)));
      newSynced[key] = await _hash(json);
    }
    for (final key in deletedHere) {
      final slash = key.indexOf('/');
      outgoing.add(RemoteRecord(
        kind: key.substring(0, slash),
        id: key.substring(slash + 1),
        payload: '',
        deleted: true,
      ));
      newSynced.remove(key);
    }
    if (outgoing.isNotEmpty) await api.push(session, outgoing);

    await store.saveSyncState(newSynced);
    if (newest != null) {
      await store.setSetting(lastPullKey, '${newest.toUtc().millisecondsSinceEpoch}');
    }
    return SyncReport(pulled: pulled, pushed: outgoing.length, applied: applied);
  }
}

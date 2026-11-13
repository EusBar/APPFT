import 'dart:convert';
import 'dart:typed_data';

import 'package:fintrack_core/fintrack_core.dart';

import 'local_store.dart';

/// Todos os dados do FINTRACK num só objeto: serve para a exportação
/// completa (JSON legível) e para a cópia de segurança cifrada.
class Snapshot {
  Snapshot({
    required this.profile,
    required this.accounts,
    required this.categories,
    required this.movements,
    required this.commitments,
    required this.budgets,
    required this.goals,
    required this.contributions,
    required this.kixikilas,
    required this.kixikilaRecords,
    required this.createdAt,
  });

  static const format = 'fintrack-snapshot';
  static const version = 1;

  final Profile profile;
  final List<Account> accounts;
  final List<Category> categories;
  final List<Movement> movements;
  final List<Commitment> commitments;
  final List<Budget> budgets;
  final List<Goal> goals;
  final List<GoalContribution> contributions;
  final List<KixikilaGroup> kixikilas;
  final List<KixikilaRecord> kixikilaRecords;
  final DateTime createdAt;

  static Future<Snapshot> read(LocalStore store) async {
    final profile = await store.loadProfile();
    if (profile == null) throw StateError('Sem perfil');
    return Snapshot(
      profile: profile,
      accounts: await store.accounts(),
      categories: await store.categories(),
      movements: await store.movements(),
      commitments: await store.commitments(),
      budgets: await store.budgets(),
      goals: await store.goals(),
      contributions: await store.goalContributions(),
      kixikilas: await store.kixikilaGroups(),
      kixikilaRecords: await store.kixikilaRecords(),
      createdAt: DateTime.now(),
    );
  }

  // --- JSON -------------------------------------------------------------------

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static Map<String, Object?> _money(Money m) => {'minor': m.minor, 'currency': m.currency.code};
  static Money _m(Object? j) {
    final map = j! as Map<String, Object?>;
    return Money(map['minor']! as int, Currency.fromCode(map['currency']! as String));
  }

  static DateTime _t(Object? v) => DateTime.fromMillisecondsSinceEpoch(v! as int);

  Map<String, Object?> toJson() => {
        'format': format,
        'version': version,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'profile': {
          'name': profile.name,
          'mainCurrency': profile.mainCurrency.code,
          'nickname': profile.nickname,
          'photo': profile.photo == null ? null : base64Encode(profile.photo!),
        },
        'accounts': [
          for (final a in accounts)
            {
              'id': a.id,
              'type': a.type.code,
              'name': a.name,
              'institution': a.institution,
              'opening': _money(a.openingBalance),
              'startDate': _d(a.startDate),
              'includeInAvailable': a.includeInAvailable,
              'archived': a.archived,
            },
        ],
        'categories': [
          for (final c in categories)
            {'id': c.id, 'kind': c.kind.code, 'name': c.name, 'icon': c.icon, 'archived': c.archived},
        ],
        'movements': [
          for (final m in movements)
            {
              'id': m.id,
              'kind': m.kind.code,
              'accountId': m.accountId,
              'amount': _money(m.amount),
              'toAccountId': m.toAccountId,
              'toAmount': m.toAmount == null ? null : _money(m.toAmount!),
              'categoryId': m.categoryId,
              'description': m.description,
              'note': m.note,
              'date': _d(m.date),
              'origin': m.origin.code,
              'reverses': m.reverses,
              'replaces': m.replaces,
              'batchId': m.batchId,
              'createdAt': m.createdAt.millisecondsSinceEpoch,
            },
        ],
        'commitments': [
          for (final c in commitments)
            {
              'id': c.id,
              'accountId': c.accountId,
              'amount': _money(c.amount),
              'categoryId': c.categoryId,
              'description': c.description,
              'note': c.note,
              'dueDate': _d(c.dueDate),
              'status': c.status.code,
              'paidMovementId': c.paidMovementId,
              'recurrence': c.recurrence.code,
              'seriesId': c.seriesId,
              'anchorDay': c.anchorDay,
              'createdAt': c.createdAt.millisecondsSinceEpoch,
            },
        ],
        'budgets': [
          for (final b in budgets)
            {
              'id': b.id,
              'categoryId': b.categoryId,
              'amount': _money(b.amount),
              'startMonth': _d(b.startMonth),
              'carryOver': b.carryOver,
              'createdAt': b.createdAt.millisecondsSinceEpoch,
            },
        ],
        'goals': [
          for (final g in goals)
            {
              'id': g.id,
              'name': g.name,
              'target': _money(g.target),
              'deadline': g.deadline == null ? null : _d(g.deadline!),
              'accountId': g.accountId,
              'archived': g.archived,
              'createdAt': g.createdAt.millisecondsSinceEpoch,
            },
        ],
        'goalContributions': [
          for (final c in contributions)
            {
              'id': c.id,
              'goalId': c.goalId,
              'amount': _money(c.amount),
              'date': _d(c.date),
              'createdAt': c.createdAt.millisecondsSinceEpoch,
            },
        ],
        'kixikilas': [
          for (final k in kixikilas)
            {
              'id': k.id,
              'name': k.name,
              'members': k.members,
              'contribution': _money(k.contribution),
              'period': k.period.code,
              'startDate': _d(k.startDate),
              'myTurn': k.myTurn,
              'accountId': k.accountId,
              'archived': k.archived,
              'createdAt': k.createdAt.millisecondsSinceEpoch,
            },
        ],
        'kixikilaRecords': [
          for (final r in kixikilaRecords)
            {
              'id': r.id,
              'groupId': r.groupId,
              'round': r.round,
              'kind': r.kind.code,
              'movementId': r.movementId,
              'createdAt': r.createdAt.millisecondsSinceEpoch,
            },
        ],
      };

  /// Reconstrói e valida tudo: qualquer campo inválido rejeita o ficheiro
  /// inteiro (nada é restaurado a meio).
  static Snapshot fromJson(Map<String, Object?> j) {
    if (j['format'] != format) throw const FormatException('Não é uma cópia do FINTRACK');
    if ((j['version'] as int? ?? 0) > version) {
      throw const FormatException('Cópia criada por uma versão mais recente do FINTRACK');
    }
    List<Map<String, Object?>> list(String key) =>
        [for (final e in (j[key] as List<Object?>? ?? const [])) e! as Map<String, Object?>];
    final p = j['profile']! as Map<String, Object?>;
    final photo = p['photo'] as String?;
    return Snapshot(
      createdAt: _t(j['createdAt']),
      profile: Profile(
        name: p['name']! as String,
        mainCurrency: Currency.fromCode(p['mainCurrency']! as String),
        nickname: p['nickname'] as String?,
        photo: photo == null ? null : Uint8List.fromList(base64Decode(photo)),
      ),
      accounts: [
        for (final a in list('accounts'))
          Account(
            id: a['id']! as String,
            type: AccountType.fromCode(a['type']! as String),
            name: a['name']! as String,
            institution: a['institution'] as String?,
            openingBalance: _m(a['opening']),
            startDate: DateTime.parse(a['startDate']! as String),
            includeInAvailable: a['includeInAvailable']! as bool,
            archived: a['archived']! as bool,
          ),
      ],
      categories: [
        for (final c in list('categories'))
          Category(
            id: c['id']! as String,
            kind: CategoryKind.fromCode(c['kind']! as String),
            name: c['name']! as String,
            icon: c['icon']! as String,
            archived: c['archived']! as bool,
          ),
      ],
      movements: [
        for (final m in list('movements'))
          Movement(
            id: m['id']! as String,
            kind: MovementKind.fromCode(m['kind']! as String),
            accountId: m['accountId']! as String,
            amount: _m(m['amount']),
            toAccountId: m['toAccountId'] as String?,
            toAmount: m['toAmount'] == null ? null : _m(m['toAmount']),
            categoryId: m['categoryId'] as String?,
            description: m['description']! as String,
            note: m['note']! as String,
            date: DateTime.parse(m['date']! as String),
            origin: MovementOrigin.fromCode(m['origin']! as String),
            reverses: m['reverses'] as String?,
            replaces: m['replaces'] as String?,
            batchId: m['batchId'] as String?,
            createdAt: _t(m['createdAt']),
          ),
      ],
      commitments: [
        for (final c in list('commitments'))
          Commitment(
            id: c['id']! as String,
            accountId: c['accountId']! as String,
            amount: _m(c['amount']),
            categoryId: c['categoryId']! as String,
            description: c['description']! as String,
            note: c['note']! as String,
            dueDate: DateTime.parse(c['dueDate']! as String),
            status: CommitmentStatus.fromCode(c['status']! as String),
            paidMovementId: c['paidMovementId'] as String?,
            recurrence: Recurrence.fromCode(c['recurrence'] as String?),
            seriesId: c['seriesId'] as String?,
            anchorDay: c['anchorDay'] as int?,
            createdAt: _t(c['createdAt']),
          ),
      ],
      budgets: [
        for (final b in list('budgets'))
          Budget(
            id: b['id']! as String,
            categoryId: b['categoryId'] as String?,
            amount: _m(b['amount']),
            startMonth: DateTime.parse(b['startMonth']! as String),
            carryOver: b['carryOver']! as bool,
            createdAt: _t(b['createdAt']),
          ),
      ],
      goals: [
        for (final g in list('goals'))
          Goal(
            id: g['id']! as String,
            name: g['name']! as String,
            target: _m(g['target']),
            deadline: g['deadline'] == null ? null : DateTime.parse(g['deadline']! as String),
            accountId: g['accountId'] as String?,
            archived: g['archived']! as bool,
            createdAt: _t(g['createdAt']),
          ),
      ],
      contributions: [
        for (final c in list('goalContributions'))
          GoalContribution(
            id: c['id']! as String,
            goalId: c['goalId']! as String,
            amount: _m(c['amount']),
            date: DateTime.parse(c['date']! as String),
            createdAt: _t(c['createdAt']),
          ),
      ],
      kixikilas: [
        for (final k in list('kixikilas'))
          KixikilaGroup(
            id: k['id']! as String,
            name: k['name']! as String,
            members: [for (final m in k['members']! as List<Object?>) m! as String],
            contribution: _m(k['contribution']),
            period: Recurrence.fromCode(k['period']! as String),
            startDate: DateTime.parse(k['startDate']! as String),
            myTurn: k['myTurn']! as int,
            accountId: k['accountId']! as String,
            archived: k['archived']! as bool,
            createdAt: _t(k['createdAt']),
          ),
      ],
      kixikilaRecords: [
        for (final r in list('kixikilaRecords'))
          KixikilaRecord(
            id: r['id']! as String,
            groupId: r['groupId']! as String,
            round: r['round']! as int,
            kind: KixikilaRecordKind.fromCode(r['kind']! as String),
            movementId: r['movementId']! as String,
            createdAt: _t(r['createdAt']),
          ),
      ],
    );
  }

  /// Coerência interna: o livro-razão aceita todos os registos.
  void validate() {
    final ids = {for (final a in accounts) a.id};
    final movementIds = <String>{};
    for (final m in movements) {
      if (!movementIds.add(m.id)) throw const FormatException('Movimento repetido na cópia');
      if (!ids.contains(m.accountId) || (m.toAccountId != null && !ids.contains(m.toAccountId))) {
        throw const FormatException('Movimento de uma conta que não existe');
      }
    }
    for (final c in commitments) {
      if (!ids.contains(c.accountId)) throw const FormatException('Compromisso de uma conta que não existe');
    }
  }

  String encodePretty() => const JsonEncoder.withIndent('  ').convert(toJson());
}

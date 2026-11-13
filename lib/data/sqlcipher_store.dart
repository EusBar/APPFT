import 'dart:typed_data';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'local_store.dart';
import 'snapshot.dart';

/// Base de dados local cifrada com SQLCipher (AES-256).
///
/// A chave é a chave de dados aleatória de 256 bits que o [PinVault] guarda
/// cifrada no Keystore/Keychain e só liberta depois do PIN certo.
class SqlCipherStoreFactory implements LocalStoreFactory {
  const SqlCipherStoreFactory();

  static const _fileName = 'fintrack.db';
  static const _version = 7;

  Future<String> _path() async => p.join(await getDatabasesPath(), _fileName);

  @override
  Future<LocalStore> open(Uint8List dataKey) async {
    final password = [
      for (final b in dataKey) b.toRadixString(16).padLeft(2, '0'),
    ].join();
    final db = await openDatabase(
      await _path(),
      password: password,
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final statement in [..._schemaV1, ..._schemaV2, ..._schemaV3, ..._schemaV4, ..._schemaV5, ..._schemaV6, ..._schemaV7]) {
          batch.execute(statement);
        }
        _seedCategories(batch);
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, from, to) async {
        final batch = db.batch();
        if (from < 2) {
          for (final statement in _schemaV2) {
            batch.execute(statement);
          }
          _seedCategories(batch);
        }
        if (from < 3) {
          for (final statement in _schemaV3) {
            batch.execute(statement);
          }
        }
        if (from < 4) {
          for (final statement in _schemaV4) {
            batch.execute(statement);
          }
        }
        if (from < 5) {
          for (final statement in _schemaV5) {
            batch.execute(statement);
          }
        }
        if (from < 6) {
          for (final statement in _schemaV6) {
            batch.execute(statement);
          }
        }
        if (from < 7) {
          for (final statement in _schemaV7) {
            batch.execute(statement);
          }
        }
        await batch.commit(noResult: true);
      },
    );
    return _SqlCipherStore(db);
  }

  @override
  Future<void> wipe() async => deleteDatabase(await _path());

  static void _seedCategories(Batch batch) {
    for (final (i, c) in Category.defaults.indexed) {
      batch.insert('categories', {
        'id': c.id,
        'kind': c.kind.code,
        'name': c.name,
        'icon': c.icon,
        'archived': 0,
        'sort': i,
      });
    }
  }

  /// Fase 2: categorias e livro-razão imutável. Os gatilhos impedem alterar
  /// ou apagar registos; cada registo só pode ser estornado uma vez.
  static const _schemaV2 = [
    '''
    CREATE TABLE categories (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      name TEXT NOT NULL,
      icon TEXT NOT NULL,
      archived INTEGER NOT NULL DEFAULT 0,
      sort INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE movements (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      account_id TEXT NOT NULL REFERENCES accounts(id),
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      currency TEXT NOT NULL,
      to_account_id TEXT REFERENCES accounts(id),
      to_amount_minor INTEGER,
      to_currency TEXT,
      category_id TEXT REFERENCES categories(id),
      description TEXT NOT NULL,
      note TEXT NOT NULL,
      date TEXT NOT NULL,
      origin TEXT NOT NULL,
      reverses_id TEXT UNIQUE REFERENCES movements(id),
      replaces_id TEXT REFERENCES movements(id),
      created_at INTEGER NOT NULL
    )''',
    'CREATE INDEX movements_account ON movements(account_id)',
    'CREATE INDEX movements_date ON movements(date)',
    _immutableUpdate,
    _immutableDelete,
  ];

  static const _immutableUpdate = '''
    CREATE TRIGGER movements_immutable_update BEFORE UPDATE ON movements
    BEGIN SELECT RAISE(ABORT, 'Livro-razão imutável: corrija com um estorno'); END''';
  static const _immutableDelete = '''
    CREATE TRIGGER movements_immutable_delete BEFORE DELETE ON movements
    BEGIN SELECT RAISE(ABORT, 'Livro-razão imutável: corrija com um estorno'); END''';

  /// Fase 3: compromissos. O estado muda (pendente, pago, cancelado), mas o
  /// pagamento é sempre uma saída no livro-razão imutável.
  static const _schemaV3 = [
    '''
    CREATE TABLE commitments (
      id TEXT PRIMARY KEY,
      account_id TEXT NOT NULL REFERENCES accounts(id),
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      currency TEXT NOT NULL,
      category_id TEXT NOT NULL REFERENCES categories(id),
      description TEXT NOT NULL,
      note TEXT NOT NULL,
      due_date TEXT NOT NULL,
      status TEXT NOT NULL,
      paid_movement_id TEXT UNIQUE REFERENCES movements(id),
      created_at INTEGER NOT NULL
    )''',
    'CREATE INDEX commitments_due ON commitments(due_date)',
  ];

  /// Etapa 1 do Bloco A: lote de importação (para anular uma importação
  /// inteira com estornos). Acrescentar uma coluna não altera registos.
  static const _schemaV4 = [
    'ALTER TABLE movements ADD COLUMN batch_id TEXT',
    'CREATE INDEX movements_batch ON movements(batch_id)',
  ];

  /// Etapa 2: perfil (alcunha, foto), compromissos recorrentes, orçamentos
  /// e objetivos.
  static const _schemaV5 = [
    'ALTER TABLE profile ADD COLUMN nickname TEXT',
    'ALTER TABLE profile ADD COLUMN photo BLOB',
    "ALTER TABLE commitments ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'none'",
    'ALTER TABLE commitments ADD COLUMN series_id TEXT',
    'ALTER TABLE commitments ADD COLUMN anchor_day INTEGER',
    '''
    CREATE TABLE budgets (
      id TEXT PRIMARY KEY,
      category_id TEXT REFERENCES categories(id),
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      currency TEXT NOT NULL,
      start_month TEXT NOT NULL,
      carry_over INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE goals (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      target_minor INTEGER NOT NULL CHECK (target_minor > 0),
      currency TEXT NOT NULL,
      deadline TEXT,
      account_id TEXT REFERENCES accounts(id),
      archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE goal_contributions (
      id TEXT PRIMARY KEY,
      goal_id TEXT NOT NULL REFERENCES goals(id),
      amount_minor INTEGER NOT NULL,
      currency TEXT NOT NULL,
      date TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )''',
  ];

  /// Etapa 4: definições internas (sessão da nuvem) e estado de sincronização.
  static const _schemaV7 = [
    'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    'CREATE TABLE sync_state (key TEXT PRIMARY KEY, hash TEXT NOT NULL)',
  ];

  /// Etapa 2B: Kixikila.
  static const _schemaV6 = [
    '''
    CREATE TABLE kixikila_groups (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      members TEXT NOT NULL,
      contribution_minor INTEGER NOT NULL CHECK (contribution_minor > 0),
      currency TEXT NOT NULL,
      period TEXT NOT NULL,
      start_date TEXT NOT NULL,
      my_turn INTEGER NOT NULL,
      account_id TEXT NOT NULL REFERENCES accounts(id),
      archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE kixikila_records (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL REFERENCES kixikila_groups(id),
      round INTEGER NOT NULL,
      kind TEXT NOT NULL,
      movement_id TEXT NOT NULL REFERENCES movements(id),
      created_at INTEGER NOT NULL
    )''',
  ];

  static const _schemaV1 = [
    '''
    CREATE TABLE profile (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      name TEXT NOT NULL,
      main_currency TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      name TEXT NOT NULL,
      institution TEXT,
      currency TEXT NOT NULL,
      opening_minor INTEGER NOT NULL,
      start_date TEXT NOT NULL,
      include_available INTEGER NOT NULL,
      archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''',
  ];
}

class _SqlCipherStore implements LocalStore {
  _SqlCipherStore(this._db);

  final Database _db;

  @override
  Future<Profile?> loadProfile() async {
    final rows = await _db.query('profile', where: 'id = 1');
    if (rows.isEmpty) return null;
    final row = rows.first;
    final photo = row['photo'];
    return Profile(
      name: row['name']! as String,
      mainCurrency: Currency.fromCode(row['main_currency']! as String),
      nickname: row['nickname'] as String?,
      photo: photo is Uint8List ? photo : photo is List<int> ? Uint8List.fromList(photo) : null,
    );
  }

  @override
  Future<void> completeOnboarding(Profile profile, Account firstAccount) {
    return _db.transaction((txn) async {
      await txn.insert('profile', {
        'id': 1,
        'name': profile.name,
        'main_currency': profile.mainCurrency.code,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await txn.insert('accounts', _accountRow(firstAccount));
    });
  }

  @override
  Future<List<Account>> accounts() async {
    final rows = await _db.query('accounts', orderBy: 'created_at, rowid');
    return [for (final r in rows) _accountFromRow(r)];
  }

  @override
  Future<void> addAccount(Account account) async {
    await _db.insert('accounts', _accountRow(account));
  }

  @override
  Future<void> updateAccount(Account account) async {
    await _db.update(
      'accounts',
      {
        'type': account.type.code,
        'name': account.name,
        'institution': account.institution,
        'opening_minor': account.openingBalance.minor,
        'start_date': _date(account.startDate),
        'include_available': account.includeInAvailable ? 1 : 0,
        'archived': account.archived ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  @override
  Future<void> deleteAccount(String id) {
    return _db.transaction((txn) async {
      final used = await txn.rawQuery(
        'SELECT (SELECT COUNT(*) FROM movements WHERE account_id = ?1 OR to_account_id = ?1) '
        '+ (SELECT COUNT(*) FROM commitments WHERE account_id = ?1) AS n',
        [id],
      );
      if ((used.first['n'] as int? ?? 0) > 0) throw StateError('Conta com histórico');
      await txn.delete('accounts', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<List<Category>> categories() async {
    final rows = await _db.query('categories', orderBy: 'sort');
    return [
      for (final r in rows)
        Category(
          id: r['id']! as String,
          kind: CategoryKind.fromCode(r['kind']! as String),
          name: r['name']! as String,
          icon: r['icon']! as String,
          archived: r['archived'] == 1,
        ),
    ];
  }

  @override
  Future<List<Movement>> movements() async {
    final rows = await _db.query('movements', orderBy: 'created_at, rowid');
    return [for (final r in rows) _movementFromRow(r)];
  }

  @override
  Future<void> append(List<Movement> records) {
    return _db.transaction((txn) async {
      for (final m in records) {
        await txn.insert(
          'movements',
          _movementRow(m),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
  }

  @override
  Future<List<Commitment>> commitments() async {
    final rows = await _db.query('commitments', orderBy: 'due_date, created_at');
    return [
      for (final r in rows)
        Commitment(
          id: r['id']! as String,
          accountId: r['account_id']! as String,
          amount: Money(r['amount_minor']! as int, Currency.fromCode(r['currency']! as String)),
          categoryId: r['category_id']! as String,
          description: r['description']! as String,
          note: r['note']! as String,
          dueDate: DateTime.parse(r['due_date']! as String),
          status: CommitmentStatus.fromCode(r['status']! as String),
          paidMovementId: r['paid_movement_id'] as String?,
          recurrence: Recurrence.fromCode(r['recurrence'] as String?),
          seriesId: r['series_id'] as String?,
          anchorDay: r['anchor_day'] as int?,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
        ),
    ];
  }

  static Map<String, Object?> _commitmentRow(Commitment c) => {
        'id': c.id,
        'account_id': c.accountId,
        'amount_minor': c.amount.minor,
        'currency': c.amount.currency.code,
        'category_id': c.categoryId,
        'description': c.description,
        'note': c.note,
        'due_date': _date(c.dueDate),
        'status': c.status.code,
        'paid_movement_id': c.paidMovementId,
        'recurrence': c.recurrence.code,
        'series_id': c.seriesId,
        'anchor_day': c.anchorDay,
        'created_at': c.createdAt.millisecondsSinceEpoch,
      };

  @override
  Future<void> saveCommitment(Commitment commitment) async {
    if (commitment.status != CommitmentStatus.pending) {
      throw StateError('Só se gravam compromissos pendentes');
    }
    await _db.insert(
      'commitments',
      _commitmentRow(commitment),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> payCommitment(Commitment commitment, Movement payment) {
    return _db.transaction((txn) async {
      await txn.insert('movements', _movementRow(payment), conflictAlgorithm: ConflictAlgorithm.abort);
      await txn.update(
        'commitments',
        {'status': CommitmentStatus.paid.code, 'paid_movement_id': payment.id},
        where: 'id = ?',
        whereArgs: [commitment.id],
      );
    });
  }

  @override
  Future<void> cancelCommitment(String id) async {
    await _db.update(
      'commitments',
      {'status': CommitmentStatus.cancelled.code, 'paid_movement_id': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> updateProfile(Profile profile) async {
    await _db.update(
      'profile',
      {'name': profile.name, 'nickname': profile.nickname, 'photo': profile.photo},
      where: 'id = 1',
    );
  }

  @override
  Future<List<Budget>> budgets() async {
    final rows = await _db.query('budgets', orderBy: 'created_at');
    return [
      for (final r in rows)
        Budget(
          id: r['id']! as String,
          categoryId: r['category_id'] as String?,
          amount: Money(r['amount_minor']! as int, Currency.fromCode(r['currency']! as String)),
          startMonth: DateTime.parse(r['start_month']! as String),
          carryOver: r['carry_over'] == 1,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
        ),
    ];
  }

  @override
  Future<void> saveBudget(Budget b) async {
    await _db.insert(
      'budgets',
      {
        'id': b.id,
        'category_id': b.categoryId,
        'amount_minor': b.amount.minor,
        'currency': b.amount.currency.code,
        'start_month': _date(b.startMonth),
        'carry_over': b.carryOver ? 1 : 0,
        'created_at': b.createdAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteBudget(String id) async {
    await _db.delete('budgets', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<Goal>> goals() async {
    final rows = await _db.query('goals', orderBy: 'created_at');
    return [
      for (final r in rows)
        Goal(
          id: r['id']! as String,
          name: r['name']! as String,
          target: Money(r['target_minor']! as int, Currency.fromCode(r['currency']! as String)),
          deadline: r['deadline'] == null ? null : DateTime.parse(r['deadline']! as String),
          accountId: r['account_id'] as String?,
          archived: r['archived'] == 1,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
        ),
    ];
  }

  @override
  Future<void> saveGoal(Goal g) async {
    await _db.insert(
      'goals',
      {
        'id': g.id,
        'name': g.name,
        'target_minor': g.target.minor,
        'currency': g.target.currency.code,
        'deadline': g.deadline == null ? null : _date(g.deadline!),
        'account_id': g.accountId,
        'archived': g.archived ? 1 : 0,
        'created_at': g.createdAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<GoalContribution>> goalContributions() async {
    final rows = await _db.query('goal_contributions', orderBy: 'date, created_at');
    return [
      for (final r in rows)
        GoalContribution(
          id: r['id']! as String,
          goalId: r['goal_id']! as String,
          amount: Money(r['amount_minor']! as int, Currency.fromCode(r['currency']! as String)),
          date: DateTime.parse(r['date']! as String),
          createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
        ),
    ];
  }

  @override
  Future<void> addGoalContribution(GoalContribution c) async {
    await _db.insert('goal_contributions', {
      'id': c.id,
      'goal_id': c.goalId,
      'amount_minor': c.amount.minor,
      'currency': c.amount.currency.code,
      'date': _date(c.date),
      'created_at': c.createdAt.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> saveCategory(Category c) async {
    final existing = await _db.query('categories', columns: ['sort'], where: 'id = ?', whereArgs: [c.id]);
    int sort;
    if (existing.isNotEmpty) {
      sort = existing.first['sort']! as int;
    } else {
      final max = await _db.rawQuery('SELECT COALESCE(MAX(sort), 0) + 1 AS n FROM categories');
      sort = max.first['n']! as int;
    }
    await _db.insert(
      'categories',
      {
        'id': c.id,
        'kind': c.kind.code,
        'name': c.name,
        'icon': c.icon,
        'archived': c.archived ? 1 : 0,
        'sort': sort,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<KixikilaGroup>> kixikilaGroups() async {
    final rows = await _db.query('kixikila_groups', orderBy: 'created_at');
    return [
      for (final r in rows)
        KixikilaGroup(
          id: r['id']! as String,
          name: r['name']! as String,
          members: (r['members']! as String).split('\n'),
          contribution: Money(r['contribution_minor']! as int, Currency.fromCode(r['currency']! as String)),
          period: Recurrence.fromCode(r['period']! as String),
          startDate: DateTime.parse(r['start_date']! as String),
          myTurn: r['my_turn']! as int,
          accountId: r['account_id']! as String,
          archived: r['archived'] == 1,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
        ),
    ];
  }

  @override
  Future<void> saveKixikilaGroup(KixikilaGroup g) async {
    await _db.insert(
      'kixikila_groups',
      {
        'id': g.id,
        'name': g.name,
        'members': g.members.join('\n'),
        'contribution_minor': g.contribution.minor,
        'currency': g.contribution.currency.code,
        'period': g.period.code,
        'start_date': _date(g.startDate),
        'my_turn': g.myTurn,
        'account_id': g.accountId,
        'archived': g.archived ? 1 : 0,
        'created_at': g.createdAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<KixikilaRecord>> kixikilaRecords() async {
    final rows = await _db.query('kixikila_records', orderBy: 'created_at');
    return [
      for (final r in rows)
        KixikilaRecord(
          id: r['id']! as String,
          groupId: r['group_id']! as String,
          round: r['round']! as int,
          kind: KixikilaRecordKind.fromCode(r['kind']! as String),
          movementId: r['movement_id']! as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
        ),
    ];
  }

  @override
  Future<void> recordKixikila(Movement movement, KixikilaRecord record) {
    return _db.transaction((txn) async {
      await txn.insert('movements', _movementRow(movement), conflictAlgorithm: ConflictAlgorithm.abort);
      await txn.insert('kixikila_records', {
        'id': record.id,
        'group_id': record.groupId,
        'round': record.round,
        'kind': record.kind.code,
        'movement_id': record.movementId,
        'created_at': record.createdAt.millisecondsSinceEpoch,
      });
    });
  }

  @override
  Future<String?> getSetting(String key) async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  @override
  Future<Map<String, String>> syncState() async {
    final rows = await _db.query('sync_state');
    return {for (final r in rows) r['key']! as String: r['hash']! as String};
  }

  @override
  Future<void> saveSyncState(Map<String, String> state) {
    return _db.transaction((txn) async {
      await txn.delete('sync_state');
      final batch = txn.batch();
      state.forEach((k, v) => batch.insert('sync_state', {'key': k, 'hash': v}));
      await batch.commit(noResult: true);
    });
  }

  /// Restauro de uma cópia: a única operação que substitui o livro-razão.
  /// Os gatilhos de imutabilidade saem e voltam dentro da mesma transação.
  @override
  Future<void> replaceAll(Snapshot snap) {
    return _db.transaction((txn) async {
      await txn.execute('DROP TRIGGER IF EXISTS movements_immutable_update');
      await txn.execute('DROP TRIGGER IF EXISTS movements_immutable_delete');
      for (final table in [
        'kixikila_records',
        'kixikila_groups',
        'goal_contributions',
        'goals',
        'budgets',
        'commitments',
        'movements',
        'categories',
        'accounts',
        'profile',
      ]) {
        await txn.delete(table);
      }
      final p = snap.profile;
      await txn.insert('profile', {
        'id': 1,
        'name': p.name,
        'main_currency': p.mainCurrency.code,
        'nickname': p.nickname,
        'photo': p.photo,
        'created_at': snap.createdAt.millisecondsSinceEpoch,
      });
      for (final a in snap.accounts) {
        await txn.insert('accounts', _accountRow(a));
      }
      for (final (i, c) in snap.categories.indexed) {
        await txn.insert('categories', {
          'id': c.id,
          'kind': c.kind.code,
          'name': c.name,
          'icon': c.icon,
          'archived': c.archived ? 1 : 0,
          'sort': i,
        });
      }
      for (final m in snap.movements) {
        await txn.insert('movements', _movementRow(m));
      }
      for (final c in snap.commitments) {
        await txn.insert('commitments', _commitmentRow(c));
      }
      for (final b in snap.budgets) {
        await txn.insert('budgets', {
          'id': b.id,
          'category_id': b.categoryId,
          'amount_minor': b.amount.minor,
          'currency': b.amount.currency.code,
          'start_month': _date(b.startMonth),
          'carry_over': b.carryOver ? 1 : 0,
          'created_at': b.createdAt.millisecondsSinceEpoch,
        });
      }
      for (final g in snap.goals) {
        await txn.insert('goals', {
          'id': g.id,
          'name': g.name,
          'target_minor': g.target.minor,
          'currency': g.target.currency.code,
          'deadline': g.deadline == null ? null : _date(g.deadline!),
          'account_id': g.accountId,
          'archived': g.archived ? 1 : 0,
          'created_at': g.createdAt.millisecondsSinceEpoch,
        });
      }
      for (final c in snap.contributions) {
        await txn.insert('goal_contributions', {
          'id': c.id,
          'goal_id': c.goalId,
          'amount_minor': c.amount.minor,
          'currency': c.amount.currency.code,
          'date': _date(c.date),
          'created_at': c.createdAt.millisecondsSinceEpoch,
        });
      }
      for (final k in snap.kixikilas) {
        await txn.insert('kixikila_groups', {
          'id': k.id,
          'name': k.name,
          'members': k.members.join('\n'),
          'contribution_minor': k.contribution.minor,
          'currency': k.contribution.currency.code,
          'period': k.period.code,
          'start_date': _date(k.startDate),
          'my_turn': k.myTurn,
          'account_id': k.accountId,
          'archived': k.archived ? 1 : 0,
          'created_at': k.createdAt.millisecondsSinceEpoch,
        });
      }
      for (final r in snap.kixikilaRecords) {
        await txn.insert('kixikila_records', {
          'id': r.id,
          'group_id': r.groupId,
          'round': r.round,
          'kind': r.kind.code,
          'movement_id': r.movementId,
          'created_at': r.createdAt.millisecondsSinceEpoch,
        });
      }
      await txn.execute(SqlCipherStoreFactory._immutableUpdate);
      await txn.execute(SqlCipherStoreFactory._immutableDelete);
    });
  }

  @override
  Future<void> close() => _db.close();

  static Map<String, Object?> _movementRow(Movement m) => {
        'id': m.id,
        'kind': m.kind.code,
        'account_id': m.accountId,
        'amount_minor': m.amount.minor,
        'currency': m.amount.currency.code,
        'to_account_id': m.toAccountId,
        'to_amount_minor': m.toAmount?.minor,
        'to_currency': m.toAmount?.currency.code,
        'category_id': m.categoryId,
        'description': m.description,
        'note': m.note,
        'date': _date(m.date),
        'origin': m.origin.code,
        'reverses_id': m.reverses,
        'replaces_id': m.replaces,
        'batch_id': m.batchId,
        'created_at': m.createdAt.millisecondsSinceEpoch,
      };

  static Movement _movementFromRow(Map<String, Object?> r) {
    final toMinor = r['to_amount_minor'] as int?;
    final toCurrency = r['to_currency'] as String?;
    return Movement(
      id: r['id']! as String,
      kind: MovementKind.fromCode(r['kind']! as String),
      accountId: r['account_id']! as String,
      amount: Money(r['amount_minor']! as int, Currency.fromCode(r['currency']! as String)),
      toAccountId: r['to_account_id'] as String?,
      toAmount: toMinor == null || toCurrency == null
          ? null
          : Money(toMinor, Currency.fromCode(toCurrency)),
      categoryId: r['category_id'] as String?,
      description: r['description']! as String,
      note: r['note']! as String,
      date: DateTime.parse(r['date']! as String),
      origin: MovementOrigin.fromCode(r['origin']! as String),
      reverses: r['reverses_id'] as String?,
      replaces: r['replaces_id'] as String?,
      batchId: r['batch_id'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
    );
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static Map<String, Object?> _accountRow(Account a) => {
        'id': a.id,
        'type': a.type.code,
        'name': a.name,
        'institution': a.institution,
        'currency': a.currency.code,
        'opening_minor': a.openingBalance.minor,
        'start_date': _date(a.startDate),
        'include_available': a.includeInAvailable ? 1 : 0,
        'archived': a.archived ? 1 : 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };

  static Account _accountFromRow(Map<String, Object?> r) {
    final currency = Currency.fromCode(r['currency']! as String);
    return Account(
      id: r['id']! as String,
      type: AccountType.fromCode(r['type']! as String),
      name: r['name']! as String,
      institution: r['institution'] as String?,
      openingBalance: Money(r['opening_minor']! as int, currency),
      startDate: DateTime.parse(r['start_date']! as String),
      includeInAvailable: r['include_available'] == 1,
      archived: r['archived'] == 1,
    );
  }
}

import 'dart:typed_data';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'local_store.dart';

/// Base de dados local cifrada com SQLCipher (AES-256).
///
/// A chave é a chave de dados aleatória de 256 bits que o [PinVault] guarda
/// cifrada no Keystore/Keychain e só liberta depois do PIN certo.
class SqlCipherStoreFactory implements LocalStoreFactory {
  const SqlCipherStoreFactory();

  static const _fileName = 'fintrack.db';
  static const _version = 2;

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
        for (final statement in [..._schemaV1, ..._schemaV2]) {
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
    '''
    CREATE TRIGGER movements_immutable_update BEFORE UPDATE ON movements
    BEGIN SELECT RAISE(ABORT, 'Livro-razão imutável: corrija com um estorno'); END''',
    '''
    CREATE TRIGGER movements_immutable_delete BEFORE DELETE ON movements
    BEGIN SELECT RAISE(ABORT, 'Livro-razão imutável: corrija com um estorno'); END''',
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
    return Profile(
      name: row['name']! as String,
      mainCurrency: Currency.fromCode(row['main_currency']! as String),
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

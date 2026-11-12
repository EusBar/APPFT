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
  static const _version = 1;

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
        for (final statement in _schemaV1) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
      },
    );
    return _SqlCipherStore(db);
  }

  @override
  Future<void> wipe() async => deleteDatabase(await _path());

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
  Future<void> close() => _db.close();

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

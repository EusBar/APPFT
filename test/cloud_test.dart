import 'dart:typed_data';

import 'package:fintrack/cloud/cloud_api.dart';
import 'package:fintrack/cloud/cloud_crypto.dart';
import 'package:fintrack/cloud/sync_engine.dart';
import 'package:fintrack/data/local_store.dart';
import 'package:fintrack/data/snapshot.dart';
import 'package:fintrack/security/pin_vault.dart';
import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> fastDerive(String pw, List<int> salt, Argon2Params _) async => Uint8List.fromList([
      for (var i = 0; i < 64; i++) (pw.codeUnitAt(i % pw.length) * 13 + salt[i % salt.length] + i) & 0xff,
    ]);

const aoa = Currency.aoa;
final day = DateTime(2026, 11, 10);
var _t = 0;

Movement expense(String id, int minor, {String description = 'Mercado'}) => Movement(
      id: id,
      kind: MovementKind.expense,
      accountId: 'a',
      amount: Money(minor, aoa),
      categoryId: 'exp.alimentacao',
      description: description,
      date: day,
      createdAt: day.add(Duration(seconds: ++_t)),
    );

Future<MemoryLocalStore> phoneWithData() async {
  final s = MemoryLocalStore();
  await s.completeOnboarding(
    const Profile(name: 'Eusébio', mainCurrency: aoa, nickname: 'EMBK'),
    Account(
      id: 'a',
      type: AccountType.bank,
      name: 'BAI',
      openingBalance: const Money(10000000, aoa),
      startDate: DateTime(2026, 11, 1),
    ),
  );
  await s.append([expense('m1', 250000)]);
  return s;
}

void main() {
  late MemoryCloudApi cloud;
  late CloudSession session;
  late CloudCrypto crypto;

  setUp(() async {
    cloud = MemoryCloudApi();
    session = await cloud.signUp('eu@exemplo.ao', 'Segura12345');
    crypto = CloudCrypto(CloudCrypto.newDataKey());
  });

  Future<SyncReport> sync(LocalStore phone) => SyncEngine(api: cloud, store: phone, crypto: crypto).run(session);
  Future<Map<String, Object?>> data(LocalStore phone) async => (await Snapshot.read(phone)).toJson()..remove('createdAt');

  test('primeiro telemóvel envia tudo, cifrado', () async {
    final a = await phoneWithData();
    final r = await sync(a);
    expect(r.pushed, greaterThan(20), reason: 'perfil, conta, categorias e movimento');
    final stored = cloud.records[session.userId]!.values;
    expect(stored.any((x) => x.payload.contains('Mercado') || x.payload.contains('Eusébio')), isFalse);
    // Segunda sincronização sem alterações não envia nada.
    expect((await sync(a)).pushed, 0);
  });

  test('telemóvel novo traz tudo e os dois ficam iguais', () async {
    final a = await phoneWithData();
    await sync(a);
    final b = MemoryLocalStore(); // acabado de instalar, sem perfil
    final r = await sync(b);
    expect(r.applied, isTrue);
    expect(await data(b), await data(a));
  });

  test('movimento feito num chega ao outro; estorno também', () async {
    final a = await phoneWithData();
    await sync(a);
    final b = MemoryLocalStore();
    await sync(b);

    final m2 = expense('m2', 100000, description: 'Táxi');
    await b.append([m2]);
    await sync(b);
    await sync(a);
    expect(a.ledger.map((m) => m.id), containsAll(['m1', 'm2']));

    await a.append([m2.reversal(id: 'r2', createdAt: day.add(const Duration(days: 1)))]);
    await sync(a);
    await sync(b);
    expect(Ledger(b.stored, b.ledger).isReversed('m2'), isTrue);
    expect(await data(b), await data(a));
  });

  test('conflito numa definição: vence o telemóvel que sincroniza depois', () async {
    final a = await phoneWithData();
    await sync(a);
    final b = MemoryLocalStore();
    await sync(b);

    await a.updateAccount(a.stored.single.copyWith(name: 'BAI ordenado'));
    await b.updateAccount(b.stored.single.copyWith(name: 'BAI principal'));
    await sync(a); // a nuvem fica com "ordenado"
    await sync(b); // b mudou também: vence b e envia
    await sync(a); // a não mudou desde então: recebe
    expect(a.stored.single.name, 'BAI principal');
    expect(b.stored.single.name, 'BAI principal');
  });

  test('apagar um orçamento propaga-se', () async {
    final a = await phoneWithData();
    await a.saveBudget(Budget(id: 'b1', amount: const Money(100000, aoa), startMonth: day, createdAt: day));
    await sync(a);
    final b = MemoryLocalStore();
    await sync(b);
    expect(b.budgetsById, contains('b1'));

    await b.deleteBudget('b1');
    await sync(b);
    await sync(a);
    expect(a.budgetsById, isEmpty);
  });

  test('a nuvem não deixa alterar movimentos', () async {
    final a = await phoneWithData();
    await sync(a);
    final before = cloud.records[session.userId]!['movement/m1']!.payload;
    await cloud.push(session, [const RemoteRecord(kind: 'movement', id: 'm1', payload: 'adulterado')]);
    expect(cloud.records[session.userId]!['movement/m1']!.payload, before);
  });

  test('chave errada não abre registos', () async {
    final a = await phoneWithData();
    await sync(a);
    final other = CloudCrypto(CloudCrypto.newDataKey());
    final b = MemoryLocalStore();
    expect(() => SyncEngine(api: cloud, store: b, crypto: other).run(session), throwsFormatException);
  });

  group('chave embrulhada e código de recuperação', () {
    test('palavra-passe e código abrem; errados não', () async {
      final key = CloudCrypto.newDataKey();
      final code = RecoveryCode.generate();
      expect(RegExp(r'^([A-Z2-9]{4}-){7}[A-Z2-9]{4}$').hasMatch(code), isTrue);
      final byPassword = await KeyWrap.wrap(key, 'Segura12345', deriver: fastDerive);
      final byCode = await KeyWrap.wrap(key, code, deriver: fastDerive);
      expect(await KeyWrap.unwrap(byPassword, 'Segura12345', deriver: fastDerive), key);
      expect(
        await KeyWrap.unwrap(byCode, RecoveryCode.normalize(code.toLowerCase().replaceAll('-', ' ')), deriver: fastDerive),
        key,
      );
      expect(() => KeyWrap.unwrap(byPassword, 'Errada12345', deriver: fastDerive), throwsFormatException);
      expect(byPassword.contains(String.fromCharCodes(key)), isFalse);
    });

    test('registos ligados ao tipo e id (o servidor não os pode trocar)', () async {
      final sealed = await crypto.seal('account', 'a', '{"x":1}');
      expect(await crypto.open('account', 'a', sealed), '{"x":1}');
      expect(() => crypto.open('account', 'b', sealed), throwsFormatException);
    });
  });
}

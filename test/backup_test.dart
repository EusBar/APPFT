import 'dart:convert';
import 'dart:typed_data';

import 'package:fintrack/data/backup.dart';
import 'package:fintrack/data/local_store.dart';
import 'package:fintrack/data/snapshot.dart';
import 'package:fintrack/security/pin_vault.dart';
import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Derivação rápida para testes (o Argon2id real é testado no PinVault).
Future<Uint8List> fastDerive(String pw, List<int> salt, Argon2Params _) async => Uint8List.fromList([
      for (var i = 0; i < 64; i++) (pw.codeUnitAt(i % pw.length) * 7 + salt[i % salt.length] + i) & 0xff,
    ]);

Future<MemoryLocalStore> sampleStore() async {
  const aoa = Currency.aoa;
  final day = DateTime(2026, 11, 3);
  final store = MemoryLocalStore();
  final account = Account(
    id: 'a',
    type: AccountType.bank,
    name: 'BAI',
    institution: 'BAI',
    openingBalance: const Money(10000000, aoa),
    startDate: DateTime(2026, 11, 1),
  );
  await store.completeOnboarding(
    Profile(name: 'Eusébio', mainCurrency: aoa, nickname: 'EMBK', photo: Uint8List.fromList([1, 2, 3])),
    account,
  );
  final m = Movement(
    id: 'm1',
    kind: MovementKind.expense,
    accountId: 'a',
    amount: const Money(250000, aoa),
    categoryId: 'exp.alimentacao',
    description: 'Mercado "Kero"; pão',
    date: day,
    createdAt: day,
  );
  await store.append([m, m.reversal(id: 'r1', createdAt: day.add(const Duration(minutes: 1)))]);
  await store.saveCommitment(Commitment(
    id: 'c1',
    accountId: 'a',
    amount: const Money(4500000, aoa),
    categoryId: 'exp.habitacao',
    description: 'Renda',
    dueDate: DateTime(2026, 11, 30),
    recurrence: Recurrence.monthly,
    createdAt: day,
  ));
  await store.saveBudget(Budget(id: 'b1', amount: const Money(100000, aoa), startMonth: day, createdAt: day));
  await store.saveGoal(Goal(id: 'g1', name: 'Viagem', target: const Money(500000, aoa), createdAt: day));
  await store.addGoalContribution(
    GoalContribution(id: 'gc', goalId: 'g1', amount: const Money(1000, aoa), date: day, createdAt: day),
  );
  await store.saveCategory(const Category(id: 'cus.1', kind: CategoryKind.expense, name: 'Ginásio', icon: 'health'));
  await store.saveKixikilaGroup(KixikilaGroup(
    id: 'k1',
    name: 'Família',
    members: ['Eu', 'Ana'],
    contribution: const Money(1000000, aoa),
    period: Recurrence.monthly,
    startDate: day,
    myTurn: 0,
    accountId: 'a',
    createdAt: day,
  ));
  return store;
}

Map<String, Object?> withoutDate(Snapshot s) => s.toJson()..remove('createdAt');

void main() {
  test('cópia cifrada: ida e volta sem perder nada', () async {
    final snap = await Snapshot.read(await sampleStore());
    final bytes = await EncryptedBackup.encrypt(snap, 'palavra-forte', deriver: fastDerive);

    // O ficheiro não contém dados legíveis.
    final text = utf8.decode(bytes);
    expect(text.contains('Mercado'), isFalse);
    expect(text.contains('Eusébio'), isFalse);

    final back = await EncryptedBackup.decrypt(bytes, 'palavra-forte', deriver: fastDerive);
    expect(withoutDate(back), withoutDate(snap));
    expect(back.profile.photo, [1, 2, 3]);
    expect(back.movements.last.reverses, 'm1');
  });

  test('palavra-passe errada, ficheiro alterado ou curta', () async {
    final snap = await Snapshot.read(await sampleStore());
    final bytes = await EncryptedBackup.encrypt(snap, 'palavra-forte', deriver: fastDerive);
    expect(
      () => EncryptedBackup.decrypt(bytes, 'outra-coisa', deriver: fastDerive),
      throwsFormatException,
    );
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    final data = base64Decode(envelope['data']! as String)..[0] ^= 0xff;
    envelope['data'] = base64Encode(data);
    expect(
      () => EncryptedBackup.decrypt(utf8.encode(jsonEncode(envelope)), 'palavra-forte', deriver: fastDerive),
      throwsFormatException,
    );
    expect(() => EncryptedBackup.encrypt(snap, 'curta', deriver: fastDerive), throwsArgumentError);
    expect(
      () => EncryptedBackup.decrypt(utf8.encode('{"format":"outro"}'), 'palavra-forte', deriver: fastDerive),
      throwsFormatException,
    );
  });

  test('restaurar substitui tudo noutro telemóvel', () async {
    final snap = await Snapshot.read(await sampleStore());
    final other = MemoryLocalStore();
    await other.replaceAll(snap);
    expect(withoutDate(await Snapshot.read(other)), withoutDate(snap));
  });

  test('exportação JSON é legível e completa', () async {
    final json = (await Snapshot.read(await sampleStore())).encodePretty();
    final map = jsonDecode(json) as Map<String, Object?>;
    expect(map['format'], 'fintrack-snapshot');
    expect((map['movements']! as List).length, 2);
    expect((map['kixikilas']! as List).length, 1);
    expect(json, contains('Mercado'));
  });
}

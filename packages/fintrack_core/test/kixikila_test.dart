import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

void main() {
  const aoa = Currency.aoa;
  final day = DateTime(2026, 11, 12);
  final account = Account(
    id: 'a',
    type: AccountType.bank,
    name: 'BAI',
    openingBalance: const Money(0, aoa),
    startDate: DateTime(2026, 1, 1),
  );

  KixikilaGroup group() => KixikilaGroup(
        id: 'k',
        name: 'Kixikila da família',
        members: ['Ana', 'Eu', 'Rui', 'Zé'],
        contribution: const Money(5000000, aoa),
        period: Recurrence.monthly,
        startDate: DateTime(2026, 10, 31),
        myTurn: 1,
        accountId: 'a',
        createdAt: day,
      );

  test('datas das rondas e valor a receber', () {
    final g = group();
    expect(g.rounds, 4);
    expect(g.payout, const Money(20000000, aoa));
    expect(g.roundDate(0), DateTime(2026, 10, 31));
    expect(g.roundDate(1), DateTime(2026, 11, 30));
    expect(g.roundDate(2), DateTime(2026, 12, 31));
    expect(g.roundDate(3), DateTime(2027, 1, 31));
  });

  test('regras do grupo', () {
    expect(
      () => KixikilaGroup(
        id: 'x',
        name: 'Só eu',
        members: ['Eu'],
        contribution: const Money(1, aoa),
        period: Recurrence.monthly,
        startDate: day,
        myTurn: 0,
        accountId: 'a',
        createdAt: day,
      ),
      throwsArgumentError,
    );
  });

  test('estado: rondas pagas, recebimento e anulação', () {
    final g = group();
    Movement mv(String id, MovementKind kind, int minor) => Movement(
          id: id,
          kind: kind,
          accountId: 'a',
          amount: Money(minor, aoa),
          categoryId: kind == MovementKind.income ? 'inc.kixikila' : 'exp.kixikila',
          date: day,
          createdAt: day,
        );
    final c0 = mv('c0', MovementKind.expense, 5000000);
    final c1 = mv('c1', MovementKind.expense, 5000000);
    final p = mv('p', MovementKind.income, 20000000);
    final records = [
      KixikilaRecord(id: '1', groupId: 'k', round: 0, kind: KixikilaRecordKind.contribution, movementId: 'c0', createdAt: day),
      KixikilaRecord(id: '2', groupId: 'k', round: 1, kind: KixikilaRecordKind.contribution, movementId: 'c1', createdAt: day),
      KixikilaRecord(id: '3', groupId: 'k', round: 1, kind: KixikilaRecordKind.payout, movementId: 'p', createdAt: day),
    ];
    final s = KixikilaEngine.status(Ledger([account], [c0, c1, p]), g, records);
    expect(s.paidRounds, {0, 1});
    expect(s.received, isTrue);
    expect(s.nextContribution, 2);
    expect(s.myPayoutDate, DateTime(2026, 11, 30));

    final undone = KixikilaEngine.status(
      Ledger([account], [c0, c1, p, c1.reversal(id: 'r', createdAt: day)]),
      g,
      records,
    );
    expect(undone.paidRounds, {0});
    expect(undone.nextContribution, 1);
  });
}

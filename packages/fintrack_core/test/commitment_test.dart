import 'dart:math';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

void main() {
  const aoa = Currency.aoa;
  final start = DateTime(2026, 11, 1);
  final today = DateTime(2026, 11, 12);
  var clock = DateTime(2026, 11, 12, 9);
  DateTime tick() => clock = clock.add(const Duration(seconds: 1));

  Account acc(String id, int opening, {AccountType t = AccountType.bank}) =>
      Account(id: id, type: t, name: id, openingBalance: Money(opening, aoa), startDate: start);

  Commitment due(String id, String account, int minor, DateTime date) => Commitment(
        id: id,
        accountId: account,
        amount: Money(minor, aoa),
        categoryId: 'exp.habitacao',
        description: 'Renda',
        dueDate: date,
        createdAt: tick(),
      );

  group('AvailableHorizon', () {
    test('fim do mês e dias', () {
      expect(AvailableHorizon.endOfMonth.end(today), DateTime(2026, 11, 30));
      expect(AvailableHorizon.endOfMonth.end(DateTime(2026, 12, 31)), DateTime(2026, 12, 31));
      expect(AvailableHorizon.endOfMonth.end(DateTime(2028, 2, 3)), DateTime(2028, 2, 29));
      expect(AvailableHorizon.days7.end(today), DateTime(2026, 11, 19));
      expect(AvailableHorizon.days90.end(today), DateTime(2027, 2, 10));
      expect(AvailableHorizon.fromCode('x'), AvailableHorizon.endOfMonth);
    });
  });

  group('Commitment', () {
    test('valor positivo e descrição obrigatória', () {
      expect(() => due('c', 'a', 0, today), throwsArgumentError);
      expect(
        () => Commitment(
          id: 'c',
          accountId: 'a',
          amount: const Money(1, aoa),
          categoryId: 'exp.outros',
          description: '  ',
          dueDate: today,
          createdAt: tick(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Saldo disponível', () {
    test('desconta pendentes até ao horizonte, incluindo atrasados', () {
      final l = Ledger([acc('a', 100000)], [], commitments: [
        due('atrasado', 'a', 1000, DateTime(2026, 11, 5)),
        due('mes', 'a', 2000, DateTime(2026, 11, 28)),
        due('dezembro', 'a', 4000, DateTime(2026, 12, 10)),
      ]);
      expect(
        l.available(today: today, horizon: AvailableHorizon.endOfMonth)[aoa],
        const Money(97000, aoa),
      );
      expect(
        l.available(today: today, horizon: AvailableHorizon.days30)[aoa],
        const Money(93000, aoa),
      );
      expect(
        l.available(today: today, horizon: AvailableHorizon.days7)[aoa],
        const Money(99000, aoa),
      );
      expect(l.balanceOf('a'), const Money(100000, aoa), reason: 'contabilístico intacto');
    });

    test('conta de poupança fora do disponível não desconta', () {
      final l = Ledger([acc('a', 100), acc('p', 5000, t: AccountType.savings)], [],
          commitments: [due('c', 'p', 1000, today)]);
      expect(l.available(today: today, horizon: AvailableHorizon.endOfMonth)[aoa], const Money(100, aoa));
    });

    test('pagar não desconta duas vezes; anular o pagamento reabre', () {
      final c = due('c', 'a', 3000, DateTime(2026, 11, 20));
      final before = Ledger([acc('a', 10000)], [], commitments: [c]);
      final availBefore = before.available(today: today, horizon: AvailableHorizon.endOfMonth);

      final pay = before.paymentFor(c, id: 'p', date: today, createdAt: tick());
      expect(before.check(pay, today: today), isNull);
      expect(pay.origin, MovementOrigin.commitment);
      final paid = c.copyWith(status: CommitmentStatus.paid, paidMovementId: 'p');
      final after = Ledger([acc('a', 10000)], [pay], commitments: [paid]);
      expect(after.statusOf(paid), CommitmentStatus.paid);
      expect(after.pending(), isEmpty);
      expect(after.available(today: today, horizon: AvailableHorizon.endOfMonth), availBefore);
      expect(after.balanceOf('a'), const Money(7000, aoa));
      expect(() => after.paymentFor(paid, id: 'p2', date: today, createdAt: tick()), throwsStateError);

      // Anular o pagamento: volta a pendente, sem escrever no compromisso.
      final cancelled = Ledger([acc('a', 10000)], [pay, pay.reversal(id: 'r', createdAt: tick())],
          commitments: [paid]);
      expect(cancelled.statusOf(paid), CommitmentStatus.pending);
      expect(cancelled.available(today: today, horizon: AvailableHorizon.endOfMonth), availBefore);

      // Corrigir o pagamento (estorno + novo registo) mantém-no pago.
      final fixed = Movement(
        id: 'p-fix',
        kind: MovementKind.expense,
        accountId: 'a',
        amount: const Money(3200, aoa),
        categoryId: 'exp.habitacao',
        date: today,
        replaces: 'p',
        createdAt: tick(),
      );
      final corrected = Ledger(
        [acc('a', 10000)],
        [pay, pay.reversal(id: 'r', createdAt: tick()), fixed],
        commitments: [paid],
      );
      expect(corrected.statusOf(paid), CommitmentStatus.paid);
      expect(corrected.paymentOf(paid)?.id, 'p-fix');
      expect(corrected.pending(), isEmpty);
    });

    test('validação de compromissos', () {
      final l = Ledger([acc('a', 0)], []);
      expect(l.checkCommitment(due('c', 'a', 10, today)), isNull);
      expect(l.checkCommitment(due('c', 'z', 10, today)), MovementIssue.unknownAccount);
      expect(
        l.checkCommitment(
          due('c', 'a', 10, today),
          category: Category.defaults.firstWhere((c) => c.kind == CategoryKind.income),
        ),
        MovementIssue.wrongCategory,
      );
    });
  });

  test('propriedade: pagar compromissos no horizonte nunca muda o disponível', () {
    final rnd = Random(7);
    for (var round = 0; round < 200; round++) {
      final accounts = [acc('a', rnd.nextInt(1000000)), acc('b', rnd.nextInt(1000000))];
      final commitments = [
        for (var i = 0; i < 8; i++)
          due('c$i', rnd.nextBool() ? 'a' : 'b', 1 + rnd.nextInt(90000),
              DateTime(2026, 11, 1 + rnd.nextInt(29))),
      ];
      var current = commitments.toList();
      final moves = <Movement>[];
      final initial = Ledger(accounts, moves, commitments: current)
          .available(today: today, horizon: AvailableHorizon.endOfMonth);

      for (var i = 0; i < commitments.length; i++) {
        if (!rnd.nextBool()) continue;
        final ledger = Ledger(accounts, moves, commitments: current);
        final pay = ledger.paymentFor(current[i], id: 'pay$i', date: today, createdAt: tick());
        moves.add(pay);
        current[i] = current[i].copyWith(status: CommitmentStatus.paid, paidMovementId: pay.id);
        // Por vezes, anula o pagamento logo a seguir.
        if (rnd.nextInt(4) == 0) moves.add(pay.reversal(id: 'rev$i', createdAt: tick()));
        final now = Ledger(accounts, moves, commitments: current)
            .available(today: today, horizon: AvailableHorizon.endOfMonth);
        expect(now, initial);
      }
    }
  });
}

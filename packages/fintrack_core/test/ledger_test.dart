import 'dart:math';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

void main() {
  const aoa = Currency.aoa;
  const usd = Currency.usd;
  final start = DateTime(2026, 11, 1);
  final today = DateTime(2026, 11, 12);
  var clock = DateTime(2026, 11, 12, 10);

  DateTime tick() => clock = clock.add(const Duration(seconds: 1));

  Account acc(String id, int opening, {Currency c = aoa, AccountType t = AccountType.bank}) =>
      Account(id: id, type: t, name: id, openingBalance: Money(opening, c), startDate: start);

  Movement income(String id, String account, int minor, {Currency c = aoa, DateTime? date}) =>
      Movement(
        id: id,
        kind: MovementKind.income,
        accountId: account,
        amount: Money(minor, c),
        categoryId: 'inc.salario',
        date: date ?? today,
        createdAt: tick(),
      );

  Movement expense(String id, String account, int minor, {String description = '', DateTime? date}) =>
      Movement(
        id: id,
        kind: MovementKind.expense,
        accountId: account,
        amount: Money(minor, aoa),
        categoryId: 'exp.alimentacao',
        description: description,
        date: date ?? today,
        createdAt: tick(),
      );

  Movement transfer(String id, String from, String to, Money sent, Money received) => Movement(
        id: id,
        kind: MovementKind.transfer,
        accountId: from,
        amount: sent,
        toAccountId: to,
        toAmount: received,
        date: today,
        createdAt: tick(),
      );

  group('Movement', () {
    test('recusa valor zero ou negativo', () {
      expect(() => expense('x', 'a', 0), throwsArgumentError);
      expect(() => expense('x', 'a', -5), throwsArgumentError);
    });

    test('transferência exige destino diferente e sem categoria', () {
      expect(
        () => transfer('t', 'a', 'a', const Money(1, aoa), const Money(1, aoa)),
        throwsArgumentError,
      );
      expect(
        () => Movement(
          id: 'x',
          kind: MovementKind.income,
          accountId: 'a',
          amount: const Money(1, aoa),
          date: today,
          createdAt: tick(),
        ),
        throwsArgumentError,
        reason: 'entrada sem categoria',
      );
    });

    test('não se estorna um estorno', () {
      final r = expense('e', 'a', 100).reversal(id: 'r', createdAt: tick());
      expect(() => r.reversal(id: 'rr', createdAt: tick()), throwsStateError);
    });
  });

  group('Ledger', () {
    test('saldo = inicial + entradas - saídas', () {
      final l = Ledger([acc('a', 10000)], [income('i', 'a', 5000), expense('e', 'a', 2500)]);
      expect(l.balanceOf('a'), const Money(12500, aoa));
    });

    test('estorno anula o efeito e sai da lista em vigor', () {
      final e = expense('e', 'a', 2500);
      final l = Ledger([acc('a', 10000)], [e, e.reversal(id: 'r', createdAt: tick())]);
      expect(l.balanceOf('a'), const Money(10000, aoa));
      expect(l.active(), isEmpty);
      expect(l.isReversed('e'), isTrue);
      expect(l.totals(start, today).expense, isEmpty);
    });

    test('correção: estorno + novo registo', () {
      final e = expense('e', 'a', 2500);
      final fixed = Movement(
        id: 'e2',
        kind: MovementKind.expense,
        accountId: 'a',
        amount: const Money(3000, aoa),
        categoryId: 'exp.alimentacao',
        date: today,
        replaces: 'e',
        createdAt: tick(),
      );
      final l = Ledger([acc('a', 10000)], [e, e.reversal(id: 'r', createdAt: tick()), fixed]);
      expect(l.balanceOf('a'), const Money(7000, aoa));
      expect(l.active().map((m) => m.id), ['e2']);
      expect(l.totals(start, today).expense[aoa], const Money(3000, aoa));
    });

    test('transferência move saldo sem contar como entrada ou saída', () {
      final l = Ledger(
        [acc('a', 10000), acc('b', 0, t: AccountType.cash)],
        [transfer('t', 'a', 'b', const Money(4000, aoa), const Money(4000, aoa))],
      );
      expect(l.balanceOf('a'), const Money(6000, aoa));
      expect(l.balanceOf('b'), const Money(4000, aoa));
      expect(l.balances()[aoa], const Money(10000, aoa));
      final t = l.totals(start, today);
      expect(t.income, isEmpty);
      expect(t.expense, isEmpty);
    });

    test('transferência entre moedas regista os dois valores', () {
      final l = Ledger(
        [acc('a', 0, c: usd), acc('b', 0)],
        [transfer('t', 'a', 'b', const Money(10000, usd), const Money(9100000, aoa))],
      );
      expect(l.balanceOf('a'), const Money(-10000, usd));
      expect(l.balanceOf('b'), const Money(9100000, aoa));
      expect(l.balances().length, 2);
    });

    test('totais do período respeitam as datas', () {
      final l = Ledger([acc('a', 0)], [
        income('i1', 'a', 100, date: DateTime(2026, 11, 2)),
        income('i2', 'a', 200, date: DateTime(2026, 11, 12)),
      ]);
      expect(l.totals(DateTime(2026, 11, 3), today).income[aoa], const Money(200, aoa));
    });

    test('validação de movimentos novos', () {
      final l = Ledger([acc('a', 0), acc('u', 0, c: usd)], [expense('e', 'a', 100)]);
      expect(l.check(expense('n', 'a', 100), today: today), isNull);
      expect(l.check(expense('n', 'zz', 100), today: today), MovementIssue.unknownAccount);
      expect(l.check(expense('n', 'u', 100), today: today), MovementIssue.currencyMismatch);
      expect(
        l.check(expense('n', 'a', 100, date: DateTime(2026, 10, 31)), today: today),
        MovementIssue.beforeAccountStart,
      );
      expect(
        l.check(expense('n', 'a', 100, date: DateTime(2026, 11, 13)), today: today),
        MovementIssue.inFuture,
      );
      final r = l.movements.first.reversal(id: 'r', createdAt: tick());
      expect(l.check(r, today: today), isNull);
      final l2 = Ledger(l.accounts.values, [...l.movements, r]);
      expect(
        l2.check(l.movements.first.reversal(id: 'r2', createdAt: tick()), today: today),
        MovementIssue.alreadyReversed,
      );
    });

    test('deteta possível duplicado', () {
      final l = Ledger([acc('a', 0)], [expense('e', 'a', 100, description: 'Pão')]);
      expect(l.possibleDuplicate(expense('n', 'a', 100, description: ' pão ')), isNotNull);
      expect(l.possibleDuplicate(expense('n', 'a', 100, description: 'Táxi')), isNull);
      expect(l.possibleDuplicate(expense('n', 'a', 101, description: 'Pão')), isNull);
    });
  });

  group('Propriedades (aleatórias, semente fixa)', () {
    test('transferências não mudam o consolidado e recalcular é estável', () {
      final rnd = Random(42);
      for (var round = 0; round < 200; round++) {
        final accounts = [
          for (var i = 0; i < 4; i++) acc('a$i', rnd.nextInt(1000000)),
        ];
        final opening = accounts.fold<int>(0, (s, a) => s + a.openingBalance.minor);
        final moves = <Movement>[];
        var expectedNet = 0;
        for (var i = 0; i < 30; i++) {
          final from = 'a${rnd.nextInt(4)}';
          final amount = 1 + rnd.nextInt(50000);
          switch (rnd.nextInt(4)) {
            case 0:
              moves.add(income('m$i', from, amount));
              expectedNet += amount;
            case 1:
              moves.add(expense('m$i', from, amount));
              expectedNet -= amount;
            case 2:
              final to = 'a${(int.parse(from.substring(1)) + 1 + rnd.nextInt(3)) % 4}';
              moves.add(transfer('m$i', from, to, Money(amount, aoa), Money(amount, aoa)));
            default:
              final candidates = moves.where((m) => !m.isReversal).toList();
              final l = Ledger(accounts, moves);
              final open = candidates.where((m) => !l.isReversed(m.id)).toList();
              if (open.isEmpty) break;
              final target = open[rnd.nextInt(open.length)];
              moves.add(target.reversal(id: 'r$i', createdAt: tick()));
              if (target.kind == MovementKind.income) expectedNet -= target.amount.minor;
              if (target.kind == MovementKind.expense) expectedNet += target.amount.minor;
          }
        }
        final ledger = Ledger(accounts, moves);
        expect(ledger.balances()[aoa]!.minor, opening + expectedNet);

        // Recalcular noutra ordem dá o mesmo resultado.
        final shuffled = Ledger(accounts, moves.toList()..shuffle(rnd));
        for (final a in accounts) {
          expect(shuffled.balanceOf(a.id), ledger.balanceOf(a.id));
        }

        // Entradas - saídas do período = variação do consolidado.
        final t = ledger.totals(start, today);
        final net = (t.income[aoa]?.minor ?? 0) - (t.expense[aoa]?.minor ?? 0);
        expect(net, expectedNet);
      }
    });
  });

  test('categorias iniciais têm identificadores únicos', () {
    final ids = Category.defaults.map((c) => c.id).toSet();
    expect(ids.length, Category.defaults.length);
  });
}

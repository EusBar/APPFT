import 'dart:math';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

void main() {
  const aoa = Currency.aoa;
  const usd = Currency.usd;
  final start = DateTime(2026, 10, 1);
  var clock = DateTime(2026, 11, 12, 8);
  DateTime tick() => clock = clock.add(const Duration(seconds: 1));

  Account acc(String id, int opening, {Currency c = aoa}) => Account(
        id: id,
        type: AccountType.bank,
        name: 'Conta $id',
        openingBalance: Money(opening, c),
        startDate: start,
      );

  Movement mv(String id, MovementKind kind, String account, int minor, DateTime date,
          {String? to, int? toMinor, Currency c = aoa, Currency? toC, String? category}) =>
      Movement(
        id: id,
        kind: kind,
        accountId: account,
        amount: Money(minor, c),
        toAccountId: to,
        toAmount: to == null ? null : Money(toMinor ?? minor, toC ?? c),
        categoryId: kind == MovementKind.transfer
            ? null
            : category ?? (kind == MovementKind.income ? 'inc.salario' : 'exp.alimentacao'),
        date: date,
        createdAt: tick(),
      );

  test('relatório mensal: abertura, fluxos, fecho e categorias', () {
    final l = Ledger([acc('a', 100000), acc('b', 0)], [
      mv('o1', MovementKind.expense, 'a', 5000, DateTime(2026, 10, 20)),
      mv('i1', MovementKind.income, 'a', 300000, DateTime(2026, 11, 1)),
      mv('e1', MovementKind.expense, 'a', 20000, DateTime(2026, 11, 3), category: 'exp.habitacao'),
      mv('e2', MovementKind.expense, 'a', 7000, DateTime(2026, 11, 4)),
      mv('t1', MovementKind.transfer, 'a', 50000, DateTime(2026, 11, 5), to: 'b'),
      mv('d1', MovementKind.expense, 'b', 1000, DateTime(2026, 12, 1)),
    ]);
    final r = PeriodReport.build(l, from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 30));
    final c = r.currencies.single;
    expect(c.opening, const Money(95000, aoa));
    expect(c.income, const Money(300000, aoa));
    expect(c.expense, const Money(27000, aoa));
    expect(c.transfersIn, const Money(50000, aoa));
    expect(c.transfersOut, const Money(50000, aoa));
    expect(c.closing, const Money(368000, aoa));
    expect(c.net, const Money(273000, aoa));
    expect(c.expenseByCategory.map((x) => x.categoryId), ['exp.habitacao', 'exp.alimentacao']);
    expect(r.movements.map((m) => m.id), ['i1', 'e1', 'e2', 't1']);
  });

  test('estornos anulam-se e moedas ficam separadas', () {
    final e = mv('e', MovementKind.expense, 'a', 4000, DateTime(2026, 11, 2));
    final l = Ledger([acc('a', 10000), acc('u', 500, c: usd)], [
      e,
      e.reversal(id: 'r', createdAt: tick()),
      mv('x', MovementKind.transfer, 'u', 100, DateTime(2026, 11, 3), to: 'a', toMinor: 91000, toC: aoa, c: usd),
    ]);
    final r = PeriodReport.build(l, from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 30));
    expect(r.currencies.map((c) => c.currency), [aoa, usd]);
    final k = r.currencies.first;
    expect(k.expense.isZero, isTrue);
    expect(k.expenseByCategory, isEmpty);
    expect(k.transfersIn, const Money(91000, aoa));
    expect(k.closing, const Money(101000, aoa));
    expect(r.currencies.last.closing, const Money(400, usd));
    expect(r.movements.map((m) => m.id), ['x']);
  });

  test('compromissos pendentes aparecem em separado', () {
    final l = Ledger([acc('a', 0)], [], commitments: [
      Commitment(
        id: 'c',
        accountId: 'a',
        amount: const Money(2500, aoa),
        categoryId: 'exp.habitacao',
        description: 'Renda',
        dueDate: DateTime(2026, 11, 28),
        createdAt: tick(),
      ),
    ]);
    final r = PeriodReport.build(l, from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 30));
    expect(r.currencies.single.pendingCommitments, const Money(2500, aoa));
    expect(r.currencies.single.closing, const Money(0, aoa), reason: 'não mexe no contabilístico');
  });

  test('propriedade: fecho = abertura + entradas − saídas + transf. recebidas − enviadas', () {
    final rnd = Random(11);
    for (var round = 0; round < 150; round++) {
      final accounts = [for (var i = 0; i < 3; i++) acc('a$i', rnd.nextInt(500000))];
      final moves = <Movement>[];
      for (var i = 0; i < 40; i++) {
        final from = 'a${rnd.nextInt(3)}';
        final date = DateTime(2026, 10, 1 + rnd.nextInt(75));
        final amount = 1 + rnd.nextInt(30000);
        switch (rnd.nextInt(4)) {
          case 0:
            moves.add(mv('m$i', MovementKind.income, from, amount, date));
          case 1:
            moves.add(mv('m$i', MovementKind.expense, from, amount, date));
          case 2:
            final to = 'a${(int.parse(from.substring(1)) + 1 + rnd.nextInt(2)) % 3}';
            moves.add(mv('m$i', MovementKind.transfer, from, amount, date, to: to));
          default:
            final open = moves.where((m) => !m.isReversal && !Ledger(accounts, moves).isReversed(m.id)).toList();
            if (open.isNotEmpty) moves.add(open[rnd.nextInt(open.length)].reversal(id: 'r$i', createdAt: tick()));
        }
      }
      final l = Ledger(accounts, moves);
      final r = PeriodReport.build(l, from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 30));
      final c = r.currencies.single;
      expect(
        c.closing.minor,
        c.opening.minor + c.income.minor - c.expense.minor + c.transfersIn.minor - c.transfersOut.minor,
      );
      final byAccount = c.accounts.fold<int>(0, (s, a) => s + a.closing.minor);
      expect(byAccount, c.closing.minor);
    }
  });

  group('MovementCsv', () {
    test('cabeçalho, decimais com vírgula e aspas', () {
      final csv = MovementCsv.encode(
        [
          Movement(
            id: 'id1',
            kind: MovementKind.expense,
            accountId: 'a',
            amount: const Money(1234567, aoa),
            categoryId: 'exp.alimentacao',
            description: 'Pão; leite e "ovos"',
            date: DateTime(2026, 11, 3),
            createdAt: tick(),
          ),
        ],
        categoryName: (_) => 'Alimentação',
        accountName: (_) => 'BAI',
        kindName: (_) => 'Saída',
      );
      final lines = csv.split('\r\n');
      expect(lines.first, startsWith('Data;Tipo;Descrição'));
      expect(lines[1], '2026-11-03;Saída;"Pão; leite e ""ovos""";Alimentação;BAI;12345,67;AOA;;;;;manual;id1');
    });

    test('neutraliza fórmulas mas mantém negativos', () {
      expect(MovementCsv.plain(const Money(-5, aoa)), '-0,05');
      final csv = MovementCsv.encode(
        [
          Movement(
            id: 'x',
            kind: MovementKind.income,
            accountId: 'a',
            amount: const Money(100, aoa),
            categoryId: 'inc.outros',
            description: '=HYPERLINK("x")',
            date: DateTime(2026, 11, 3),
            createdAt: tick(),
          ),
        ],
        categoryName: (_) => 'Outros',
        accountName: (_) => 'BAI',
        kindName: (_) => 'Entrada',
      );
      expect(csv, contains(";\"'=HYPERLINK(\"\"x\"\")\";"));
    });
  });
}

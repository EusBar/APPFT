import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

String plain(String s) => s.replaceAll(' ', ' ');

void main() {
  const aoa = Currency.aoa;
  const salary = MonthCycle(25);
  final today = DateTime(2026, 11, 22); // mês "novembro" = 25 out a 24 nov
  final bank = Account(
    id: 'b',
    type: AccountType.bank,
    name: 'BAI',
    openingBalance: const Money(10000000, aoa),
    startDate: DateTime(2026, 1, 1),
  );
  var n = 0;
  Movement out(int kz, String cat, DateTime d) => Movement(
        id: 'm${n++}',
        kind: MovementKind.expense,
        accountId: 'b',
        amount: Money(kz * 100, aoa),
        categoryId: cat,
        date: d,
        createdAt: d,
      );
  Commitment due(String id, int kz, DateTime d) => Commitment(
        id: id,
        accountId: 'b',
        amount: Money(kz * 100, aoa),
        categoryId: 'exp.habitacao',
        description: 'Renda $id',
        dueDate: d,
        createdAt: DateTime(2026, 10, 1),
      );
  final ledger = Ledger(
    [bank],
    [
      out(10000, 'exp.alimentacao', DateTime(2026, 10, 26)), // novembro (salário)
      out(4000, 'exp.alimentacao', DateTime(2026, 11, 10)), // novembro
      out(3000, 'exp.transporte', DateTime(2026, 10, 20)), // outubro (salário)
    ],
    commitments: [due('a', 20000, DateTime(2026, 11, 24)), due('b', 50000, DateTime(2026, 11, 26))],
  );

  test('saldo disponível: "fim do mês" é a véspera do dia do salário', () {
    expect(AvailableHorizon.endOfMonth.end(today, cycle: salary), DateTime(2026, 11, 24));
    final committed = ledger.committed(today: today, horizon: AvailableHorizon.endOfMonth, cycle: salary)[aoa]!;
    expect(committed, const Money(2000000, aoa), reason: 'só a renda de dia 24');
    final calendar = ledger.committed(today: today, horizon: AvailableHorizon.endOfMonth)[aoa]!;
    expect(calendar, const Money(7000000, aoa), reason: 'no calendário entram as duas');
  });

  test('orçamentos contam o mês financeiro', () {
    final b = Budget(
      id: 'o',
      categoryId: 'exp.alimentacao',
      amount: const Money(2000000, aoa),
      startMonth: DateTime(2026, 11),
      createdAt: DateTime(2026, 10, 1),
    );
    final s = BudgetEngine.status(ledger, b, month: DateTime(2026, 11), today: today, cycle: salary);
    expect(s.spent, const Money(1400000, aoa));
    expect(s.percent, 70);
    // 29 dias decorridos de 31: estimativa = 14 000 x 31 / 29.
    expect(s.projected, Money(1400000 * 31 ~/ 29, aoa));
    final cal = BudgetEngine.status(ledger, b, month: DateTime(2026, 11), today: today);
    expect(cal.spent, const Money(400000, aoa), reason: 'no calendário só conta o dia 10');
  });

  test('perguntas usam o mês financeiro', () {
    final ask = AskEngine(ledger: ledger, categories: Category.defaults, currency: aoa, today: today, cycle: salary);
    expect(plain(ask.ask('Quanto gastei este mês?').text), contains('14 000,00'));
    expect(plain(ask.ask('Quanto gastei no mês passado?').text), contains('3 000,00'));
    expect(plain(ask.ask('Quanto posso gastar?').text), contains('Pode gastar 63 000,00'));
  });

  test('tendências: meses com o nome certo', () {
    final months = TrendsEngine.months(ledger, aoa, today: today, count: 2, cycle: salary);
    expect([for (final m in months) m.month.month], [10, 11]);
    expect(months.last.expense, const Money(1400000, aoa));
    expect(months.first.expense, const Money(300000, aoa));
  });
}

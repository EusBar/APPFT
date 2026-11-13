import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

void main() {
  const aoa = Currency.aoa;
  final today = DateTime(2026, 11, 13);
  var n = 0;
  final bai = Account(
    id: 'bai',
    type: AccountType.bank,
    name: 'BAI',
    openingBalance: const Money(50000000, aoa),
    startDate: DateTime(2026, 1, 1),
  );

  Movement out(int kz, String cat, DateTime d) => Movement(
        id: 'm${n++}',
        kind: MovementKind.expense,
        accountId: 'bai',
        amount: Money(kz * 100, aoa),
        categoryId: cat,
        date: d,
        createdAt: d,
      );
  Movement inc(int kz, DateTime d) => Movement(
        id: 'm${n++}',
        kind: MovementKind.income,
        accountId: 'bai',
        amount: Money(kz * 100, aoa),
        categoryId: 'inc.salario',
        date: d,
        createdAt: d,
      );

  late Ledger ledger;
  setUp(() {
    ledger = Ledger([bai], [
      // Setembro e outubro: transporte ~20 000 por mês.
      out(20000, 'exp.transporte', DateTime(2026, 9, 10)),
      out(20000, 'exp.transporte', DateTime(2026, 10, 10)),
      out(30000, 'exp.alimentacao', DateTime(2026, 10, 5)),
      inc(200000, DateTime(2026, 10, 1)),
      // Novembro até dia 13.
      out(35000, 'exp.transporte', DateTime(2026, 11, 3)),
      out(15000, 'exp.alimentacao', DateTime(2026, 11, 12)),
    ]);
  });

  AskEngine engine() => AskEngine(
        ledger: ledger,
        categories: Category.defaults,
        currency: aoa,
        today: today,
      );

  test('normaliza acentos e pontuação', () {
    expect(AskEngine.normalize('Quanto GASTEI em Alimentação?'), 'quanto gastei em alimentacao');
  });

  test('total do mês e por categoria', () {
    final a = engine().ask('Quanto gastei este mês?');
    expect(a.text, contains('50 000,00'));
    expect(a.lines.first, startsWith('Transporte'));
    final b = engine().ask('quanto gastei em transportes no mês passado');
    expect(b.text, contains('20 000,00'));
    expect(b.text, contains('Transporte'));
    expect(b.text, contains('mês passado'));
  });

  test('mês pelo nome e entradas', () {
    expect(engine().ask('Quanto gastei em outubro?').text, contains('50 000,00'));
    expect(engine().ask('Quanto recebi este ano?').text, contains('200 000,00'));
  });

  test('categoria onde gasta mais', () {
    final a = engine().ask('Em que gasto mais?');
    expect(a.text, contains('Transporte'));
    expect(a.text, contains('70%'));
  });

  test('comparação com o mês passado', () {
    final a = engine().ask('Compara com o mês passado');
    // Até dia 13: 50 000 agora contra 20 000 + 30 000 (dias 5 e 10) = 50 000.
    expect(a.text, contains('o mesmo que'));
  });

  test('pergunta desconhecida mostra exemplos', () {
    final a = engine().ask('qual é a capital de França');
    expect(a.understood, isFalse);
    expect(a.lines, AskEngine.examples);
  });

  test('saldo', () {
    final a = engine().ask('Qual é o meu saldo?');
    // 500 000 + 200 000 − 120 000 = 580 000
    expect(a.text, contains('580 000,00'));
  });

  test('tendências: categoria acima do habitual e poupança', () {
    final list = TrendsEngine.insights(ledger, aoa, today: today, categoryName: (id) => id);
    final ids = [for (final i in list) i.id];
    expect(ids, contains('cat:exp.transporte'));
    expect(ids, contains('savings'));
    final months = TrendsEngine.months(ledger, aoa, today: today);
    expect(months, hasLength(6));
    expect(months.last.expense, const Money(5000000, aoa));
  });
}

import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

void main() {
  const aoa = Currency.aoa;
  final today = DateTime(2026, 11, 13);
  var clock = DateTime(2026, 11, 1);
  DateTime tick() => clock = clock.add(const Duration(minutes: 1));

  final bai = Account(
    id: 'bai',
    type: AccountType.bank,
    name: 'Conta à ordem',
    institution: 'BAI',
    openingBalance: const Money(10000000, aoa),
    startDate: DateTime(2026, 1, 1),
  );
  final cash = Account(
    id: 'cash',
    type: AccountType.cash,
    name: 'Carteira',
    openingBalance: const Money(500000, aoa),
    startDate: DateTime(2026, 1, 1),
  );

  EntryDraft parse(String text, {List<Account>? accounts}) => SmartEntryParser.parse(
        text,
        accounts: accounts ?? [bai, cash],
        categories: Category.defaults,
        today: today,
      );

  group('Smart Entry', () {
    test('frase completa', () {
      final d = parse('Despesa de 12 500 Kz em alimentação, hoje, conta BAI');
      expect(d.kind, MovementKind.expense);
      expect(d.amount, const Money(1250000, aoa));
      expect(d.categoryId, 'exp.alimentacao');
      expect(d.accountId, 'bai');
      expect(d.date, today);
      expect(d.dateAssumed, isFalse);
      expect(d.complete, isTrue);
    });

    test('linguagem do dia a dia', () {
      final d = parse('gastei 3 mil no táxi ontem em dinheiro');
      expect(d.kind, MovementKind.expense);
      expect(d.amount, const Money(300000, aoa));
      expect(d.categoryId, 'exp.transporte');
      expect(d.accountId, 'cash');
      expect(d.date, DateTime(2026, 11, 12));
    });

    test('SMS do banco colado', () {
      final d = parse('BAI: Debito de 45.000,00 AOA na conta ****1234 em 03/11/2026 - PAGAMENTO EPAL');
      expect(d.kind, MovementKind.expense);
      expect(d.amount, const Money(4500000, aoa));
      expect(d.date, DateTime(2026, 11, 3));
      expect(d.accountId, 'bai');
      expect(d.categoryId, 'exp.habitacao');
    });

    test('salário', () {
      final d = parse('Recebi o salário 350 000 kz no BAI');
      expect(d.kind, MovementKind.income);
      expect(d.categoryId, 'inc.salario');
      expect(d.amount, const Money(35000000, aoa));
    });

    test('pergunta quando falta: nunca adivinha conta nem moeda', () {
      final d = parse('paguei 20 000');
      expect(d.missing, contains(EntryField.account), reason: 'duas contas, nenhuma indicada');
      expect(d.missing, contains(EntryField.amount), reason: 'sem conta não sabe a moeda');
      expect(d.dateAssumed, isTrue);
      final one = parse('paguei 20 000', accounts: [bai]);
      expect(one.accountId, 'bai');
      expect(one.amount, const Money(2000000, aoa));
      expect(one.missing, contains(EntryField.category));
    });

    test('moeda diferente da conta é assinalada', () {
      final d = parse('gastei 50 USD no BAI');
      expect(d.missing, contains(EntryField.account));
      expect(d.notes.single, contains('USD'));
    });
  });

  group('Validador de números', () {
    test('aceita só números vindos do motor', () {
      final v = NumberValidator([
        {'total': const Money(1250050, aoa).format(), 'count': 4, 'percent': 37},
      ]);
      expect(v.accepts('Gastou 12 500,50 Kz em 4 movimentos (37% do mês).'), isTrue);
      expect(v.accepts('Gastou 12 500,50 Kz.'), isTrue);
      expect(v.unverified('Gastou 13 000 Kz.'), ['13 000']);
      expect(v.unverified('Poupe 50 000 por mês.'), ['50 000']);
    });

    test('dias, contagens pequenas e anos não são valores', () {
      final v = NumberValidator(const []);
      expect(v.accepts('Até dia 30 de novembro de 2026, nas 3 categorias.'), isTrue);
      expect(v.accepts('Tem 45 movimentos.'), isFalse);
    });
  });

  group('AI Guard', () {
    Movement food(String id, int minor, DateTime date, {String account = 'bai'}) => Movement(
          id: id,
          kind: MovementKind.expense,
          accountId: account,
          amount: Money(minor, aoa),
          categoryId: 'exp.alimentacao',
          date: date,
          createdAt: tick(),
        );

    test('duplicado, valor fora do padrão e disponível negativo', () {
      final history = [for (var i = 0; i < 8; i++) food('h$i', 1000000 + i * 10000, DateTime(2026, 10, 1 + i))];
      final ledger = Ledger([bai], [
        ...history,
        food('big', 9000000, DateTime(2026, 11, 10)),
        food('d1', 250000, DateTime(2026, 11, 11)),
        food('d2', 250000, DateTime(2026, 11, 11)),
      ], commitments: [
        Commitment(
          id: 'c',
          accountId: 'bai',
          amount: const Money(50000000, aoa),
          categoryId: 'exp.habitacao',
          description: 'Renda',
          dueDate: DateTime(2026, 11, 28),
          createdAt: tick(),
        ),
      ]);
      final alerts = AiGuard.scan(ledger, today: today);
      final kinds = alerts.map((a) => a.kind).toSet();
      expect(kinds, {GuardKind.duplicate, GuardKind.unusualAmount, GuardKind.availableNegative});
      final big = alerts.firstWhere((a) => a.kind == GuardKind.unusualAmount);
      expect(big.movementId, 'big');
      expect(big.typical!.minor, greaterThan(1000000));
      expect(alerts.first.priority, 3);

      // Dispensar um alerta ("é legítimo") esconde-o.
      final dup = alerts.firstWhere((a) => a.kind == GuardKind.duplicate);
      expect(AiGuard.scan(ledger, today: today, dismissed: {dup.id}).any((a) => a.id == dup.id), isFalse);
    });

    test('com poucos dados não julga valores', () {
      final ledger = Ledger([bai], [food('a', 100, today), food('b', 999999, today)]);
      expect(AiGuard.scan(ledger, today: today).where((a) => a.kind == GuardKind.unusualAmount), isEmpty);
    });
  });
}

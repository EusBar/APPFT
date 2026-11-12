import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

void main() {
  const aoa = Currency.aoa;
  final start = DateTime(2026, 9, 1);
  var clock = DateTime(2026, 11, 12, 8);
  DateTime tick() => clock = clock.add(const Duration(seconds: 1));

  final bank = Account(
    id: 'a',
    type: AccountType.bank,
    name: 'BAI',
    openingBalance: const Money(10000000, aoa),
    startDate: start,
  );
  final savings = Account(
    id: 's',
    type: AccountType.savings,
    name: 'Poupança',
    openingBalance: const Money(0, aoa),
    startDate: start,
  );

  Movement expense(String id, int minor, DateTime date, {String category = 'exp.alimentacao', String description = ''}) =>
      Movement(
        id: id,
        kind: MovementKind.expense,
        accountId: 'a',
        amount: Money(minor, aoa),
        categoryId: category,
        description: description,
        date: date,
        createdAt: tick(),
      );

  group('Orçamentos', () {
    final food = Budget(
      id: 'b',
      categoryId: 'exp.alimentacao',
      amount: const Money(100000, aoa),
      startMonth: DateTime(2026, 10),
      createdAt: start,
    );

    test('consumo, patamares e transferências fora', () {
      final l = Ledger([bank, savings], [
        expense('e1', 30000, DateTime(2026, 11, 2)),
        expense('e2', 25000, DateTime(2026, 11, 5)),
        expense('x', 99999, DateTime(2026, 11, 5), category: 'exp.habitacao'),
        Movement(
          id: 't',
          kind: MovementKind.transfer,
          accountId: 'a',
          amount: const Money(50000, aoa),
          toAccountId: 's',
          toAmount: const Money(50000, aoa),
          date: DateTime(2026, 11, 6),
          createdAt: tick(),
        ),
      ]);
      final s = BudgetEngine.status(l, food, month: DateTime(2026, 11), today: DateTime(2026, 11, 10));
      expect(s.spent, const Money(55000, aoa));
      expect(s.remaining, const Money(45000, aoa));
      expect(s.percent, 55);
      expect(s.level, BudgetLevel.half);
      expect(s.projected, const Money(165000, aoa), reason: '55 000 em 10 dias → 30 dias');

      final global = Budget(id: 'g', amount: const Money(150000, aoa), startMonth: DateTime(2026, 11), createdAt: start);
      final g = BudgetEngine.status(l, global, month: DateTime(2026, 11), today: DateTime(2026, 11, 10));
      expect(g.spent, const Money(154999, aoa), reason: 'todas as despesas, sem a transferência');
      expect(g.level, BudgetLevel.exceeded);
    });

    test('estornos devolvem o orçamento', () {
      final e = expense('e', 90000, DateTime(2026, 11, 2));
      final l = Ledger([bank], [e, e.reversal(id: 'r', createdAt: tick())]);
      expect(BudgetEngine.status(l, food, month: DateTime(2026, 11), today: DateTime(2026, 11, 3)).spent.isZero, isTrue);
    });

    test('transporte do saldo de meses anteriores', () {
      final l = Ledger([bank], [expense('o', 70000, DateTime(2026, 10, 9))]);
      final carry = food.copyWith(carryOver: true);
      final s = BudgetEngine.status(l, carry, month: DateTime(2026, 11), today: DateTime(2026, 11, 1));
      expect(s.limit, const Money(130000, aoa), reason: 'sobraram 30 000 em outubro');
      expect(BudgetEngine.status(l, food, month: DateTime(2026, 11), today: DateTime(2026, 11, 1)).limit,
          const Money(100000, aoa));
      expect(BudgetEngine.status(l, food, month: DateTime(2026, 10), today: DateTime(2026, 11, 1)).projected, isNull);
    });
  });

  group('Objetivos', () {
    test('com conta associada: progresso = saldo reservado', () {
      final l = Ledger([bank, savings], [
        Movement(
          id: 't',
          kind: MovementKind.transfer,
          accountId: 'a',
          amount: const Money(250000, aoa),
          toAccountId: 's',
          toAmount: const Money(250000, aoa),
          date: DateTime(2026, 11, 1),
          createdAt: tick(),
        ),
      ]);
      final goal = Goal(
        id: 'g',
        name: 'Viagem',
        target: const Money(1000000, aoa),
        deadline: DateTime(2027, 4, 30),
        accountId: 's',
        createdAt: start,
      );
      final p = GoalEngine.progress(l, goal, const [], today: DateTime(2026, 11, 12));
      expect(p.saved, const Money(250000, aoa));
      expect(p.percent, 25);
      expect(p.milestone, 25);
      expect(p.remaining, const Money(750000, aoa));
      expect(p.monthlyNeeded, const Money(125000, aoa), reason: '750 000 em 6 meses');
    });

    test('planeado: soma das contribuições, incluindo retiradas', () {
      final goal = Goal(id: 'g', name: 'Carro', target: const Money(1000, aoa), createdAt: start);
      final p = GoalEngine.progress(Ledger([bank], []), goal, [
        GoalContribution(id: '1', goalId: 'g', amount: const Money(800, aoa), date: start, createdAt: start),
        GoalContribution(id: '2', goalId: 'g', amount: const Money(-100, aoa), date: start, createdAt: start),
        GoalContribution(id: '3', goalId: 'outro', amount: const Money(999, aoa), date: start, createdAt: start),
      ], today: DateTime(2026, 11, 12));
      expect(p.saved, const Money(700, aoa));
      expect(p.monthlyNeeded, isNull);
      expect(p.done, isFalse);
    });
  });

  group('Recorrência', () {
    test('mensal mantém o dia 31 depois de fevereiro', () {
      final c = Commitment(
        id: 'c1',
        accountId: 'a',
        amount: const Money(100, aoa),
        categoryId: 'exp.habitacao',
        description: 'Renda',
        dueDate: DateTime(2027, 1, 31),
        recurrence: Recurrence.monthly,
        createdAt: start,
      );
      final feb = c.nextOccurrence(id: 'c2', createdAt: start)!;
      expect(feb.dueDate, DateTime(2027, 2, 28));
      expect(feb.seriesId, 'c1');
      expect(feb.status, CommitmentStatus.pending);
      final mar = feb.nextOccurrence(id: 'c3', createdAt: start)!;
      expect(mar.dueDate, DateTime(2027, 3, 31));
      expect(Recurrence.weekly.next(DateTime(2026, 12, 29)), DateTime(2027, 1, 5));
      expect(Recurrence.yearly.next(DateTime(2028, 2, 29)), DateTime(2029, 2, 28));
      expect(Recurrence.none.next(DateTime(2026)), isNull);
    });
  });

  group('Categorização local', () {
    test('aprende com o histórico do utilizador', () {
      final s = CategorySuggester([
        expense('1', 1, start, description: 'Kero Talatona', category: 'exp.alimentacao'),
        expense('2', 1, start, description: 'Kero Kilamba', category: 'exp.alimentacao'),
        expense('3', 1, start, description: 'Táxi para o trabalho', category: 'exp.transporte'),
        expense('4', 1, start, description: 'Renda casa', category: 'exp.habitacao'),
      ]);
      expect(s.suggest('kero  talatona', MovementKind.expense, Category.defaults), 'exp.alimentacao');
      expect(s.suggest('Compras no Kero', MovementKind.expense, Category.defaults), 'exp.alimentacao');
      expect(s.suggest('taxi', MovementKind.expense, Category.defaults), 'exp.transporte');
      expect(s.suggest('algo novo', MovementKind.expense, Category.defaults), isNull);
      expect(s.suggest('Kero', MovementKind.income, Category.defaults), isNull);
    });
  });
}


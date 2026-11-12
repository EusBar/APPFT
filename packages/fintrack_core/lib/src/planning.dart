import 'category.dart';
import 'ledger.dart';
import 'money.dart';
import 'movement.dart';
import 'names.dart';

// --- Orçamentos ---------------------------------------------------------------

/// Orçamento mensal: global (sem categoria) ou de uma categoria de despesa.
/// Vale todos os meses a partir de [startMonth], até ser alterado.
class Budget {
  Budget({
    required this.id,
    this.categoryId,
    required this.amount,
    required DateTime startMonth,
    this.carryOver = false,
    required this.createdAt,
  }) : startMonth = DateTime(startMonth.year, startMonth.month) {
    if (amount.minor <= 0) {
      throw ArgumentError.value(amount, 'amount', 'O orçamento tem de ser positivo');
    }
  }

  final String id;

  /// `null` = orçamento global (todas as despesas na moeda).
  final String? categoryId;
  final Money amount;
  final DateTime startMonth;

  /// Transporta o que sobrou (ou faltou) do mês anterior.
  final bool carryOver;
  final DateTime createdAt;

  bool get isGlobal => categoryId == null;

  Budget copyWith({Money? amount, bool? carryOver}) => Budget(
        id: id,
        categoryId: categoryId,
        amount: amount ?? this.amount,
        startMonth: startMonth,
        carryOver: carryOver ?? this.carryOver,
        createdAt: createdAt,
      );
}

/// Patamares de alerta (secção 8).
enum BudgetLevel { ok, half, warning, exceeded }

class BudgetStatus {
  const BudgetStatus({
    required this.budget,
    required this.limit,
    required this.spent,
    required this.projected,
  });

  final Budget budget;

  /// Valor do mês, já com o transporte do mês anterior.
  final Money limit;
  final Money spent;

  /// Estimativa de consumo até ao fim do mês (ritmo atual). `null` fora do
  /// mês corrente. É sempre apresentada como estimativa.
  final Money? projected;

  Money get remaining => limit - spent;

  /// Percentagem consumida (inteira, pode passar de 100).
  int get percent => limit.minor <= 0 ? 100 : (spent.minor * 100) ~/ limit.minor;

  BudgetLevel get level => percent >= 100
      ? BudgetLevel.exceeded
      : percent >= 80
          ? BudgetLevel.warning
          : percent >= 50
              ? BudgetLevel.half
              : BudgetLevel.ok;
}

class BudgetEngine {
  /// Despesas do mês na moeda do orçamento, estornos incluídos.
  /// Transferências próprias nunca contam.
  static Money spent(Ledger ledger, Budget b, DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1, 0);
    var minor = 0;
    for (final m in ledger.movements) {
      if (m.kind != MovementKind.expense) continue;
      if (m.amount.currency != b.amount.currency) continue;
      if (m.date.isBefore(start) || m.date.isAfter(end)) continue;
      if (b.categoryId != null && m.categoryId != b.categoryId) continue;
      final account = ledger.accounts[m.accountId];
      if (account == null) continue;
      minor += m.isReversal ? -m.amount.minor : m.amount.minor;
    }
    return Money(minor, b.amount.currency);
  }

  static BudgetStatus status(Ledger ledger, Budget b, {required DateTime month, required DateTime today}) {
    final m = DateTime(month.year, month.month);
    var limit = b.amount;
    if (b.carryOver) {
      // Soma o saldo de cada mês anterior desde o início do orçamento.
      var cursor = b.startMonth;
      var carry = 0;
      while (cursor.isBefore(m)) {
        carry += b.amount.minor - spent(ledger, b, cursor).minor;
        cursor = DateTime(cursor.year, cursor.month + 1);
      }
      limit = Money(b.amount.minor + carry, b.amount.currency);
    }
    final used = spent(ledger, b, m);
    Money? projected;
    if (today.year == m.year && today.month == m.month) {
      final days = DateTime(m.year, m.month + 1, 0).day;
      projected = Money((used.minor * days) ~/ today.day, used.currency);
    }
    return BudgetStatus(budget: b, limit: limit, spent: used, projected: projected);
  }
}

// --- Objetivos ----------------------------------------------------------------

/// Objetivo financeiro (secção 12). Com conta associada, o progresso é o
/// saldo dessa conta (dinheiro reservado); sem conta, é a soma das
/// contribuições registadas (objetivo apenas planeado).
class Goal {
  Goal({
    required this.id,
    required String name,
    required this.target,
    this.deadline,
    this.accountId,
    this.archived = false,
    required this.createdAt,
  }) : name = _name(name) {
    if (target.minor <= 0) throw ArgumentError.value(target, 'target', 'Valor pretendido inválido');
  }

  static String _name(String n) {
    final clean = NameRules.clean(n);
    if (clean == null) throw ArgumentError.value(n, 'name', 'Nome inválido');
    return clean;
  }

  final String id;
  final String name;
  final Money target;
  final DateTime? deadline;
  final String? accountId;
  final bool archived;
  final DateTime createdAt;

  bool get isReserved => accountId != null;

  Goal copyWith({String? name, Money? target, DateTime? deadline, bool clearDeadline = false, bool? archived}) =>
      Goal(
        id: id,
        name: name ?? this.name,
        target: target ?? this.target,
        deadline: clearDeadline ? null : deadline ?? this.deadline,
        accountId: accountId,
        archived: archived ?? this.archived,
        createdAt: createdAt,
      );
}

class GoalContribution {
  GoalContribution({
    required this.id,
    required this.goalId,
    required this.amount,
    required DateTime date,
    required this.createdAt,
  }) : date = DateTime(date.year, date.month, date.day) {
    if (amount.minor == 0) throw ArgumentError.value(amount, 'amount', 'Contribuição vazia');
  }

  final String id;
  final String goalId;

  /// Positivo para juntar, negativo para retirar.
  final Money amount;
  final DateTime date;
  final DateTime createdAt;
}

class GoalProgress {
  const GoalProgress({required this.goal, required this.saved, required this.monthlyNeeded});

  final Goal goal;
  final Money saved;

  /// Quanto juntar por mês para cumprir o prazo; `null` sem prazo ou já
  /// cumprido.
  final Money? monthlyNeeded;

  Money get remaining {
    final r = goal.target.minor - saved.minor;
    return Money(r < 0 ? 0 : r, goal.target.currency);
  }

  int get percent => saved.minor <= 0 ? 0 : (saved.minor * 100) ~/ goal.target.minor;

  /// Último marco atingido: 0, 25, 50, 75 ou 100.
  int get milestone => percent >= 100 ? 100 : (percent ~/ 25) * 25;

  bool get done => saved.minor >= goal.target.minor;
}

class GoalEngine {
  static GoalProgress progress(
    Ledger ledger,
    Goal goal,
    Iterable<GoalContribution> contributions, {
    required DateTime today,
  }) {
    final cur = goal.target.currency;
    int saved;
    final accountId = goal.accountId;
    if (accountId != null && ledger.accounts.containsKey(accountId)) {
      saved = ledger.balanceOf(accountId).minor;
    } else {
      saved = 0;
      for (final c in contributions) {
        if (c.goalId == goal.id && c.amount.currency == cur) saved += c.amount.minor;
      }
    }
    Money? monthly;
    final deadline = goal.deadline;
    final remaining = goal.target.minor - saved;
    if (deadline != null && remaining > 0) {
      var months = (deadline.year - today.year) * 12 + deadline.month - today.month;
      if (deadline.day >= today.day) months += 1;
      if (months < 1) months = 1;
      monthly = Money((remaining + months - 1) ~/ months, cur);
    }
    return GoalProgress(goal: goal, saved: Money(saved, cur), monthlyNeeded: monthly);
  }
}

// --- Categorização local (Smart Categorize, sem nuvem) -------------------------

/// Sugere a categoria a partir do histórico do próprio utilizador: primeiro
/// descrições iguais, depois palavras em comum. Corre no dispositivo.
class CategorySuggester {
  CategorySuggester(Iterable<Movement> history) {
    for (final m in history) {
      final cat = m.categoryId;
      if (cat == null || m.isReversal || m.description.isEmpty) continue;
      final key = '${m.kind.code}|${_norm(m.description)}';
      (_exact[key] ??= {})[cat] = (_exact[key]?[cat] ?? 0) + 1;
      for (final w in _words(m.description)) {
        final wk = '${m.kind.code}|$w';
        (_byWord[wk] ??= {})[cat] = (_byWord[wk]?[cat] ?? 0) + 1;
      }
    }
  }

  final Map<String, Map<String, int>> _exact = {};
  final Map<String, Map<String, int>> _byWord = {};

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static const _stop = {'de', 'da', 'do', 'das', 'dos', 'e', 'em', 'no', 'na', 'a', 'o', 'para', 'com', 'por'};

  static Iterable<String> _words(String s) =>
      _norm(s).split(' ').where((w) => w.length >= 3 && !_stop.contains(w) && int.tryParse(w) == null);

  /// Melhor categoria para [description], ou `null` sem pistas suficientes.
  String? suggest(String description, MovementKind kind, Iterable<Category> categories) {
    if (kind == MovementKind.transfer) return null;
    final wanted = kind == MovementKind.income ? CategoryKind.income : CategoryKind.expense;
    final valid = {for (final c in categories) if (c.kind == wanted && !c.archived) c.id};
    String? best(Map<String, int>? votes) {
      if (votes == null) return null;
      String? top;
      var n = 0;
      votes.forEach((cat, count) {
        if (valid.contains(cat) && count > n) {
          top = cat;
          n = count;
        }
      });
      return top;
    }

    final exact = best(_exact['${kind.code}|${_norm(description)}']);
    if (exact != null) return exact;
    final score = <String, int>{};
    for (final w in _words(description)) {
      _byWord['${kind.code}|$w']?.forEach((cat, count) {
        if (valid.contains(cat)) score[cat] = (score[cat] ?? 0) + count;
      });
    }
    return best(score);
  }
}

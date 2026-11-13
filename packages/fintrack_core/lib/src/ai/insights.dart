import '../currency.dart';
import '../ledger.dart';
import '../money.dart';
import '../movement.dart';

/// Entradas e saídas de um mês, numa moeda.
class MonthFlow {
  const MonthFlow({required this.month, required this.income, required this.expense});

  /// Primeiro dia do mês.
  final DateTime month;
  final Money income;
  final Money expense;

  Money get net => income - expense;
}

enum InsightTone { good, warning, info }

/// Uma observação sobre os números, calculada no telemóvel.
class Insight {
  const Insight({required this.id, required this.tone, required this.title, required this.detail});

  final String id;
  final InsightTone tone;
  final String title;
  final String detail;
}

/// Tendências e análises locais (sem Internet): só estatística simples sobre
/// o livro-razão, por isso cada número é exato e verificável.
class TrendsEngine {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _monthStart(DateTime d, [int back = 0]) => DateTime(d.year, d.month - back, 1);
  static DateTime _monthEnd(DateTime start) => DateTime(start.year, start.month + 1, 0);

  /// Soma (em unidades mínimas) de entradas ou saídas entre duas datas.
  static int _sum(Ledger ledger, MovementKind kind, Currency cur, DateTime from, DateTime to, {String? categoryId}) {
    var total = 0;
    for (final m in ledger.active()) {
      if (m.kind != kind || m.amount.currency != cur) continue;
      if (m.date.isBefore(from) || m.date.isAfter(to)) continue;
      if (categoryId != null && m.categoryId != categoryId) continue;
      total += m.amount.minor;
    }
    return total;
  }

  /// Total de saídas ou entradas num período (opcionalmente por categoria).
  static Money total(
    Ledger ledger,
    MovementKind kind,
    Currency currency, {
    required DateTime from,
    required DateTime to,
    String? categoryId,
  }) =>
      Money(_sum(ledger, kind, currency, _day(from), _day(to), categoryId: categoryId), currency);

  /// Saídas por categoria num período, da maior para a menor.
  static List<(String categoryId, Money total)> byCategory(
    Ledger ledger,
    Currency currency, {
    required DateTime from,
    required DateTime to,
    MovementKind kind = MovementKind.expense,
  }) {
    final f = _day(from), t = _day(to);
    final sums = <String, int>{};
    for (final m in ledger.active()) {
      if (m.kind != kind || m.amount.currency != currency || m.categoryId == null) continue;
      if (m.date.isBefore(f) || m.date.isAfter(t)) continue;
      sums[m.categoryId!] = (sums[m.categoryId!] ?? 0) + m.amount.minor;
    }
    final list = [for (final e in sums.entries) (e.key, Money(e.value, currency))];
    list.sort((a, b) => b.$2.minor.compareTo(a.$2.minor));
    return list;
  }

  /// Os últimos [count] meses (o atual até hoje), do mais antigo para o atual.
  static List<MonthFlow> months(Ledger ledger, Currency currency, {required DateTime today, int count = 6}) {
    final t = _day(today);
    return [
      for (var i = count - 1; i >= 0; i--)
        () {
          final start = _monthStart(t, i);
          final end = i == 0 ? t : _monthEnd(start);
          return MonthFlow(
            month: start,
            income: Money(_sum(ledger, MovementKind.income, currency, start, end), currency),
            expense: Money(_sum(ledger, MovementKind.expense, currency, start, end), currency),
          );
        }(),
    ];
  }

  /// Observações sobre o mês corrente, por ordem de importância.
  static List<Insight> insights(
    Ledger ledger,
    Currency currency, {
    required DateTime today,
    required String Function(String categoryId) categoryName,
  }) {
    final t = _day(today);
    final out = <Insight>[];
    final start = _monthStart(t);
    final daysInMonth = _monthEnd(start).day;
    final spent = _sum(ledger, MovementKind.expense, currency, start, t);
    final earned = _sum(ledger, MovementKind.income, currency, start, t);
    String fmt(int minor) => Money(minor, currency).format();

    // 1. Ritmo face ao mesmo período do mês passado.
    final prevStart = _monthStart(t, 1);
    final prevEnd = _monthEnd(prevStart);
    final prevSameDay = DateTime(prevStart.year, prevStart.month, t.day > prevEnd.day ? prevEnd.day : t.day);
    final prevSpent = _sum(ledger, MovementKind.expense, currency, prevStart, prevSameDay);
    if (prevSpent > 0 && spent > 0) {
      final change = ((spent - prevSpent) * 100 / prevSpent).round();
      if (change.abs() >= 10) {
        out.add(Insight(
          id: 'pace',
          tone: change > 0 ? InsightTone.warning : InsightTone.good,
          title: change > 0 ? 'Está a gastar $change% mais' : 'Está a gastar ${-change}% menos',
          detail: 'Até dia ${t.day}: ${fmt(spent)} este mês, contra ${fmt(prevSpent)} no mesmo período do mês passado.',
        ));
      }
    }

    // 2. Projeção do mês ao ritmo atual (só com dias suficientes).
    if (t.day >= 5 && spent > 0 && t.day < daysInMonth) {
      final projected = spent * daysInMonth ~/ t.day;
      out.add(Insight(
        id: 'projection',
        tone: earned > 0 && projected > earned ? InsightTone.warning : InsightTone.info,
        title: 'Ao ritmo atual, o mês fecha em ${fmt(projected)}',
        detail: 'Média de ${fmt(spent ~/ t.day)} por dia em saídas.'
            '${earned > 0 && projected > earned ? ' É mais do que as entradas do mês (${fmt(earned)}).' : ''}',
      ));
    }

    // 3. Categorias acima da média dos 3 meses anteriores.
    final current = byCategory(ledger, currency, from: start, to: t);
    for (final (id, total) in current.take(6)) {
      var sum = 0, months = 0;
      for (var i = 1; i <= 3; i++) {
        final s = _monthStart(t, i);
        final v = _sum(ledger, MovementKind.expense, currency, s, _monthEnd(s), categoryId: id);
        if (v > 0) {
          sum += v;
          months++;
        }
      }
      if (months < 2) continue;
      final avg = sum ~/ months;
      if (avg > 0 && total.minor > avg * 12 ~/ 10) {
        out.add(Insight(
          id: 'cat:$id',
          tone: InsightTone.warning,
          title: '${categoryName(id)} acima do habitual',
          detail: 'Já vai em ${total.format()} este mês; a média mensal é ${fmt(avg)}.',
        ));
      }
    }

    // 4. Peso da maior categoria.
    if (current.isNotEmpty && spent > 0) {
      final (id, top) = current.first;
      final share = (top.minor * 100 / spent).round();
      if (share >= 30 && current.length > 1) {
        out.add(Insight(
          id: 'top',
          tone: InsightTone.info,
          title: '${categoryName(id)} é $share% das saídas',
          detail: '${top.format()} de ${fmt(spent)} este mês.',
        ));
      }
    }

    // 5. Taxa de poupança do mês passado.
    final prevIncome = _sum(ledger, MovementKind.income, currency, prevStart, prevEnd);
    final prevExpense = _sum(ledger, MovementKind.expense, currency, prevStart, prevEnd);
    if (prevIncome > 0) {
      final rate = ((prevIncome - prevExpense) * 100 / prevIncome).round();
      out.add(Insight(
        id: 'savings',
        tone: rate >= 10 ? InsightTone.good : InsightTone.warning,
        title: rate >= 0 ? 'No mês passado poupou $rate% do que recebeu' : 'No mês passado gastou mais do que recebeu',
        detail: 'Entradas ${fmt(prevIncome)}, saídas ${fmt(prevExpense)}.'
            '${rate < 10 ? ' Uma meta comum é guardar pelo menos 10%.' : ''}',
      ));
    }

    // 6. Sem entradas registadas este mês.
    if (earned == 0 && spent > 0 && t.day >= 10) {
      out.add(const Insight(
        id: 'noincome',
        tone: InsightTone.info,
        title: 'Ainda sem entradas este mês',
        detail: 'Registe o salário ou outras entradas para ver quanto está a poupar.',
      ));
    }
    return out;
  }
}

/// Um fator do pulso financeiro.
class PulseFactor {
  const PulseFactor(this.label, {required this.ok});
  final String label;
  final bool ok;
}

/// Pulso financeiro: uma nota de 0 a 100, calculada no telemóvel a partir de
/// regras simples e explicáveis (cada fator aparece ao utilizador).
class FinancialPulse {
  const FinancialPulse({required this.score, required this.label, required this.factors});

  final int score;
  final String label;
  final List<PulseFactor> factors;

  /// `null` quando ainda não há movimentos para avaliar.
  static FinancialPulse? compute(
    Ledger ledger,
    Currency currency, {
    required DateTime today,
    required int availableMinor,
    List<int> budgetPercents = const [],
  }) {
    final t = DateTime(today.year, today.month, today.day);
    if (!ledger.active().any((m) => m.kind != MovementKind.transfer && m.amount.currency == currency)) return null;
    var score = 0;
    final factors = <PulseFactor>[];

    // 1. Poupança (35): último mês completo com entradas, senão o atual.
    var start = DateTime(t.year, t.month - 1, 1);
    var end = DateTime(t.year, t.month, 0);
    var income = TrendsEngine._sum(ledger, MovementKind.income, currency, start, end);
    if (income == 0) {
      start = DateTime(t.year, t.month, 1);
      end = t;
      income = TrendsEngine._sum(ledger, MovementKind.income, currency, start, end);
    }
    final expense = TrendsEngine._sum(ledger, MovementKind.expense, currency, start, end);
    if (income > 0) {
      final rate = (income - expense) * 100 ~/ income;
      score += rate >= 20 ? 35 : rate <= 0 ? 0 : rate * 35 ~/ 20;
      factors.add(PulseFactor(rate >= 0 ? 'Poupa $rate% do que recebe' : 'Gasta mais do que recebe', ok: rate >= 10));
    } else {
      factors.add(const PulseFactor('Sem entradas registadas', ok: false));
    }

    // 2. Disponível depois dos compromissos (20).
    if (availableMinor >= 0) {
      score += 20;
      factors.add(const PulseFactor('Compromissos cobertos', ok: true));
    } else {
      factors.add(const PulseFactor('Faltam fundos para os compromissos', ok: false));
    }

    // 3. Ritmo face ao mês passado (15).
    final prevStart = DateTime(t.year, t.month - 1, 1);
    final prevEnd = DateTime(t.year, t.month, 0);
    final same = DateTime(prevStart.year, prevStart.month, t.day > prevEnd.day ? prevEnd.day : t.day);
    final now = TrendsEngine._sum(ledger, MovementKind.expense, currency, DateTime(t.year, t.month, 1), t);
    final before = TrendsEngine._sum(ledger, MovementKind.expense, currency, prevStart, same);
    if (before == 0 || now <= before) {
      score += 15;
      factors.add(const PulseFactor('Gastos controlados', ok: true));
    } else {
      final over = (now - before) * 100 ~/ before;
      score += over >= 50 ? 0 : 15 - over * 15 ~/ 50;
      factors.add(PulseFactor('Gastos $over% acima do mês passado', ok: over < 10));
    }

    // 4. Orçamentos (20): sem orçamentos conta metade.
    if (budgetPercents.isEmpty) {
      score += 10;
      factors.add(const PulseFactor('Sem orçamentos definidos', ok: false));
    } else {
      final within = budgetPercents.where((p) => p < 100).length;
      score += within * 20 ~/ budgetPercents.length;
      factors.add(PulseFactor('$within de ${budgetPercents.length} orçamentos no limite', ok: within == budgetPercents.length));
    }

    // 5. Compromissos em atraso (10).
    final late = ledger.pending().where((c) => c.dueDate.isBefore(t)).length;
    if (late == 0) {
      score += 10;
    } else {
      factors.add(PulseFactor('$late ${late == 1 ? 'compromisso' : 'compromissos'} em atraso', ok: false));
    }

    final s = score.clamp(0, 100);
    final label = s >= 80
        ? 'Excelente'
        : s >= 60
            ? 'Saudável'
            : s >= 40
                ? 'Atenção'
                : 'Em risco';
    return FinancialPulse(score: s, label: label, factors: factors);
  }
}

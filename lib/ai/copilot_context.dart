import 'package:fintrack_core/fintrack_core.dart';

import '../design/labels.dart';
import '../finance/finance_data.dart';

/// Resumo mínimo dos números para o Copilot (secção 13: dados minimizados).
///
/// Só totais, saldos, prazos e nomes que o utilizador deu a contas,
/// categorias, compromissos e objetivos. Nunca vão descrições de movimentos,
/// observações, fotografias, e-mail, nomes de pessoas da Kixikila nem
/// identificadores.
Map<String, Object?> copilotContext(
  FinanceData data, {
  required DateTime today,
  required AvailableHorizon horizon,
}) {
  final ledger = data.ledger;
  final day = DateTime(today.year, today.month, today.day);
  String fmt(Money m) => m.format();
  String date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Map<String, String> byCurrency(Map<Currency, Money> m) => {for (final e in m.entries) e.key.code: fmt(e.value)};

  // Últimos 3 meses: entradas, saídas e saídas por categoria.
  final months = <Map<String, Object?>>[];
  for (var i = 0; i < 3; i++) {
    final start = DateTime(day.year, day.month - i, 1);
    final end = i == 0 ? day : DateTime(start.year, start.month + 1, 0);
    final totals = ledger.totals(start, end);
    final byCategory = <String, Map<Currency, int>>{};
    for (final m in ledger.movements) {
      if (m.kind != MovementKind.expense) continue;
      if (m.date.isBefore(start) || m.date.isAfter(end)) continue;
      final name = data.category(m.categoryId)?.name ?? 'Outros';
      final cur = byCategory.putIfAbsent(name, () => {});
      final signed = m.isReversal ? -m.amount.minor : m.amount.minor;
      cur[m.amount.currency] = (cur[m.amount.currency] ?? 0) + signed;
    }
    final categories = <String, String>{};
    final entries = [
      for (final c in byCategory.entries)
        for (final v in c.value.entries)
          if (v.value > 0) (c.key, Money(v.value, v.key)),
    ]..sort((a, b) => b.$2.minor.compareTo(a.$2.minor));
    for (final (name, money) in entries.take(12)) {
      final key = byCategory[name]!.length > 1 ? '$name (${money.currency.code})' : name;
      categories[key] = fmt(money);
    }
    months.add({
      'mes': '${start.year}-${start.month.toString().padLeft(2, '0')}',
      if (i == 0) 'ate_hoje': true,
      'entradas': byCurrency(totals.income),
      'saidas': byCurrency(totals.expense),
      'saidas_por_categoria': categories,
    });
  }

  final pending = ledger.pending();
  final budgets = [
    for (final b in data.budgets)
      () {
        final s = BudgetEngine.status(ledger, b, month: day, today: day);
        return {
          'categoria': b.categoryId == null ? 'Global (todas as saídas)' : data.category(b.categoryId)?.name ?? 'Outros',
          'limite': fmt(s.limit),
          'gasto': fmt(s.spent),
          'restante': fmt(s.remaining),
          'percentagem': s.percent,
          if (s.projected != null) 'estimativa_fim_do_mes': fmt(s.projected!),
        };
      }(),
  ];
  final goals = [
    for (final g in data.goals)
      if (!g.archived)
        () {
          final p = GoalEngine.progress(ledger, g, data.contributions, today: day);
          return {
            'nome': g.name,
            'objetivo': fmt(g.target),
            'juntado': fmt(p.saved),
            'falta': fmt(p.remaining),
            'percentagem': p.percent,
            if (g.deadline != null) 'prazo': date(g.deadline!),
            if (p.monthlyNeeded != null) 'juntar_por_mes': fmt(p.monthlyNeeded!),
          };
        }(),
  ];

  return {
    'hoje': date(day),
    'contas': [
      for (final a in data.openAccounts)
        {
          'nome': a.name,
          'tipo': accountTypeLabel(a.type),
          'saldo': fmt(ledger.balanceOf(a.id)),
          if (!a.includeInAvailable) 'fora_do_disponivel': true,
        },
    ],
    'saldo_total': byCurrency(ledger.balances()),
    'disponivel': {
      'valor': byCurrency(ledger.available(today: day, horizon: horizon)),
      'explicacao': 'Saldos incluídos menos compromissos pendentes até ${horizonLabel(horizon).toLowerCase()}',
    },
    'compromissos_pendentes': [
      for (final c in pending.take(15))
        {
          'descricao': c.description,
          'valor': fmt(c.amount),
          'data': date(c.dueDate),
          if (c.dueDate.isBefore(day)) 'atrasado': true,
        },
    ],
    'meses': months,
    'orcamentos': budgets,
    'objetivos': goals,
  };
}

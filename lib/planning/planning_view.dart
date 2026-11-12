import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../finance/finance_data.dart';
import 'budgets_view.dart';
import 'commitments_view.dart';
import 'goals_view.dart';
import 'kixikila_view.dart';

enum PlanSection { commitments, budgets, goals, kixikila }

String planSectionLabel(PlanSection s) => switch (s) {
      PlanSection.commitments => 'Compromissos',
      PlanSection.budgets => 'Orçamentos',
      PlanSection.goals => 'Objetivos',
      PlanSection.kixikila => 'Kixikila',
    };

IconData planSectionIcon(PlanSection s) => switch (s) {
      PlanSection.commitments => Icons.event_note_outlined,
      PlanSection.budgets => Icons.donut_large,
      PlanSection.goals => Icons.flag_outlined,
      PlanSection.kixikila => Icons.groups_outlined,
    };

/// Separador Planear: compromissos, orçamentos, objetivos e Kixikila.
class PlanningView extends StatelessWidget {
  const PlanningView({
    super.key,
    required this.data,
    required this.discreet,
    required this.section,
    required this.onSection,
  });

  final FinanceData data;
  final bool discreet;
  final PlanSection section;
  final ValueChanged<PlanSection> onSection;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(FtSpace.lg, FtSpace.sm, FtSpace.lg, 96),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in PlanSection.values)
                Padding(
                  padding: const EdgeInsets.only(right: FtSpace.sm),
                  child: ChoiceChip(
                    avatar: Icon(planSectionIcon(s), size: 18),
                    label: Text(planSectionLabel(s)),
                    selected: section == s,
                    onSelected: (_) => onSection(s),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: FtSpace.md),
        switch (section) {
          PlanSection.commitments => CommitmentsView(data: data, discreet: discreet),
          PlanSection.budgets => BudgetsView(data: data, discreet: discreet),
          PlanSection.goals => GoalsView(data: data, discreet: discreet),
          PlanSection.kixikila => KixikilaView(data: data, discreet: discreet),
        },
      ],
    );
  }
}

/// Estado de uma secção do Planear, numa frase curta.
class PlanSignal {
  const PlanSignal(this.text, this.level);
  final String text;

  /// 0 = vazio/neutro, 1 = bom, 2 = atenção, 3 = alerta.
  final int level;
}

PlanSignal planSignal(FinanceData data, PlanSection s, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final ledger = data.ledger;
  switch (s) {
    case PlanSection.commitments:
      final pending = ledger.pending();
      if (pending.isEmpty) return const PlanSignal('Nada pendente', 0);
      final overdue = pending.where((c) => c.dueDate.isBefore(today)).length;
      if (overdue > 0) return PlanSignal('$overdue em atraso', 3);
      final week = pending.where((c) => !c.dueDate.isAfter(today.add(const Duration(days: 7)))).length;
      if (week > 0) return PlanSignal('$week esta semana', 2);
      return PlanSignal('${pending.length} pendente${pending.length == 1 ? '' : 's'}', 1);
    case PlanSection.budgets:
      if (data.budgets.isEmpty) return const PlanSignal('Definir', 0);
      final month = DateTime(now.year, now.month);
      final statuses = [for (final b in data.budgets) BudgetEngine.status(ledger, b, month: month, today: now)];
      final over = statuses.where((x) => x.level == BudgetLevel.exceeded).length;
      if (over > 0) return PlanSignal('$over ultrapassado${over == 1 ? '' : 's'}', 3);
      final near = statuses.where((x) => x.level == BudgetLevel.warning).length;
      if (near > 0) return PlanSignal('$near perto do limite', 2);
      return const PlanSignal('Dentro do limite', 1);
    case PlanSection.goals:
      final goals = [for (final g in data.goals) if (!g.archived) g];
      if (goals.isEmpty) return const PlanSignal('Criar', 0);
      final progress = [for (final g in goals) GoalEngine.progress(ledger, g, data.contributions, today: now)];
      final best = progress.reduce((a, b) => a.percent >= b.percent ? a : b);
      return PlanSignal(goals.length == 1 ? '${best.percent}% concluído' : '${goals.length} ativos · até ${best.percent}%', 1);
    case PlanSection.kixikila:
      final groups = [for (final g in data.kixikilas) if (!g.archived) g];
      if (groups.isEmpty) return const PlanSignal('Acompanhar', 0);
      DateTime? soonest;
      for (final g in groups) {
        final st = KixikilaEngine.status(ledger, g, data.kixikilaRecords);
        final n = st.nextContribution;
        if (n == null) continue;
        final d = g.roundDate(n);
        if (soonest == null || d.isBefore(soonest)) soonest = d;
      }
      if (soonest == null) return const PlanSignal('Em dia', 1);
      if (soonest.isBefore(today)) return const PlanSignal('Contribuição atrasada', 3);
      final days = soonest.difference(today).inDays;
      return PlanSignal(days == 0 ? 'Contribuição hoje' : 'Próxima em $days dias', days <= 3 ? 2 : 1);
  }
}

/// Resumo discreto do Planear para o Início: uma linha por secção, com o
/// estado e um ponto de cor. Toque para abrir a secção.
class PlanningSummaryCard extends StatelessWidget {
  const PlanningSummaryCard({super.key, required this.data, required this.onOpen});

  final FinanceData data;
  final ValueChanged<PlanSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    Color dot(int level) => switch (level) {
          3 => colors.expense,
          2 => colors.alert,
          1 => colors.income,
          _ => scheme.onSurfaceVariant.withValues(alpha: 0.4),
        };

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(FtRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.fromLTRB(FtSpace.md, FtSpace.md, FtSpace.md, FtSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'PLANEAR',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: FtSpace.xs),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3.1,
            children: [
              for (final s in PlanSection.values)
                Builder(builder: (context) {
                  final signal = planSignal(data, s, now);
                  return InkWell(
                    borderRadius: BorderRadius.circular(FtRadius.md),
                    onTap: () => onOpen(s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: FtSpace.xs),
                      child: Row(
                        children: [
                          Icon(planSectionIcon(s), size: 18, color: scheme.onSurfaceVariant),
                          const SizedBox(width: FtSpace.sm),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(planSectionLabel(s), style: theme.textTheme.labelLarge, maxLines: 1),
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(color: dot(signal.level), shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        signal.text,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ],
      ),
    );
  }
}

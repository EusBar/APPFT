import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../finance/finance_data.dart';
import 'budgets_view.dart';
import 'commitments_view.dart';
import 'goals_view.dart';

enum PlanSection { commitments, budgets, goals }

String planSectionLabel(PlanSection s) => switch (s) {
      PlanSection.commitments => 'Compromissos',
      PlanSection.budgets => 'Orçamentos',
      PlanSection.goals => 'Objetivos',
    };

/// Separador Planear: compromissos, orçamentos e objetivos.
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
        SegmentedButton<PlanSection>(
          showSelectedIcon: false,
          segments: [
            for (final s in PlanSection.values)
              ButtonSegment(value: s, label: Text(planSectionLabel(s), maxLines: 1)),
          ],
          selected: {section},
          onSelectionChanged: (v) => onSection(v.first),
        ),
        const SizedBox(height: FtSpace.md),
        switch (section) {
          PlanSection.commitments => CommitmentsView(data: data, discreet: discreet),
          PlanSection.budgets => BudgetsView(data: data, discreet: discreet),
          PlanSection.goals => GoalsView(data: data, discreet: discreet),
        },
      ],
    );
  }
}

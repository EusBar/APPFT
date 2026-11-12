import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';

import '../design/labels.dart';
import '../design/tokens.dart';

/// Fluxo do mês: resultado líquido em destaque, barra proporcional entre
/// entradas e saídas e taxa de poupança. Valores vêm sempre do livro-razão.
class MonthFlowCard extends StatelessWidget {
  const MonthFlowCard({
    super.key,
    required this.ledger,
    required this.today,
    required this.mainCurrency,
    required this.discreet,
  });

  final Ledger ledger;
  final DateTime today;
  final Currency mainCurrency;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totals = ledger.totals(DateTime(today.year, today.month), today);
    final currencies = <Currency>{...totals.income.keys, ...totals.expense.keys};
    if (currencies.isEmpty) currencies.add(mainCurrency);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FtRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerHighest.withValues(alpha: 0.78),
            scheme.surfaceContainerHigh.withValues(alpha: 0.62),
          ],
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(FtSpace.lg, FtSpace.lg, FtSpace.lg, FtSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FLUXO DE ${monthName(today.month).toUpperCase()}',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          for (final (i, c) in currencies.indexed) ...[
            if (i > 0) const Divider(height: FtSpace.xl),
            _CurrencyFlow(
              income: totals.income[c] ?? Money.zero(c),
              expense: totals.expense[c] ?? Money.zero(c),
              discreet: discreet,
            ),
          ],
        ],
      ),
    );
  }
}

class _CurrencyFlow extends StatelessWidget {
  const _CurrencyFlow({required this.income, required this.expense, required this.discreet});

  final Money income;
  final Money expense;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final muted = theme.colorScheme.onSurfaceVariant;
    final net = income - expense;
    final netColor = net.isNegative
        ? colors.expense
        : net.isZero
            ? theme.colorScheme.onSurface
            : colors.income;
    final netText = discreet
        ? '••••••'
        : '${net.isNegative ? '−' : net.isZero ? '' : '+'}${Money(net.minor.abs(), net.currency).format()}';

    // Taxa de poupança, em inteiros: (entradas − saídas) / entradas.
    final rate = income.minor > 0 ? (net.minor * 100) ~/ income.minor : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: FtSpace.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  netText,
                  semanticsLabel: discreet ? 'Resultado oculto' : null,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFeatures: ftAmountFeatures,
                    fontWeight: FontWeight.w700,
                    color: netColor,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            if (rate != null && !discreet)
              Container(
                margin: const EdgeInsets.only(left: FtSpace.sm, bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: FtSpace.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: (rate >= 0 ? colors.income : colors.expense).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(FtRadius.lg),
                ),
                child: Text(
                  rate >= 0 ? 'Poupança $rate%' : 'Défice ${-rate}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: rate >= 0 ? colors.income : colors.expense,
                    fontWeight: FontWeight.w700,
                    fontFeatures: ftAmountFeatures,
                  ),
                ),
              ),
          ],
        ),
        Text('Resultado líquido', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(height: FtSpace.md),
        _SplitBar(income: income.minor, expense: expense.minor),
        const SizedBox(height: FtSpace.md),
        Row(
          children: [
            Expanded(
              child: _Legend(
                color: colors.income,
                label: 'Entradas',
                value: amountText(income, discreet: discreet),
              ),
            ),
            const SizedBox(width: FtSpace.md),
            Expanded(
              child: _Legend(
                color: colors.expense,
                label: 'Saídas',
                value: amountText(expense, discreet: discreet),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Barra fina com a proporção entre entradas e saídas.
class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.income, required this.expense});

  final int income;
  final int expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final total = income + expense;
    const height = 6.0;
    final track = BoxDecoration(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(height),
    );
    if (total == 0) return Container(height: height, decoration: track);

    int flex(int v) => v == 0 ? 0 : ((v * 1000) ~/ total).clamp(1, 1000);
    final fi = flex(income);
    final fe = flex(expense);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          if (fi > 0)
            Expanded(
              flex: fi,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.income,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          if (fi > 0 && fe > 0) const SizedBox(width: 3),
          if (fe > 0)
            Expanded(
              flex: fe,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.expense,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: FtSpace.xs),
            Text(label, style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontFeatures: ftAmountFeatures,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

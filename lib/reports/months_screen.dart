import 'dart:typed_data';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../design/labels.dart';
import '../design/plate.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../premium/paywall_screen.dart';
import '../premium/premium.dart';
import '../security/session.dart';
import '../settings/settings_screen.dart';
import 'month_export.dart';
import 'report_screen.dart';

/// Resumos mensais: cada mês financeiro com o que entrou, o que saiu e o
/// saldo. Toque num mês para ver as categorias e exportar (PDF ou Excel).
class MonthsScreen extends ConsumerStatefulWidget {
  const MonthsScreen({super.key});

  @override
  ConsumerState<MonthsScreen> createState() => _MonthsScreenState();
}

class _MonthsScreenState extends ConsumerState<MonthsScreen> {
  bool _busy = false;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Meses desde o primeiro movimento (no máximo 3 anos), do mais recente.
  List<FinancialMonth> _months(FinanceData data, MonthCycle cycle) {
    final all = cycle.recent(_today, count: 36);
    final movements = data.ledger.active();
    if (movements.isEmpty) return all.take(1).toList();
    final first = movements.map((m) => m.date).reduce((a, b) => a.isBefore(b) ? a : b);
    return [for (final m in all) if (!m.to.isBefore(first)) m];
  }

  Future<void> _exportYear(FinanceData data, MonthCycle cycle, List<FinancialMonth> months) async {
    if (!ref.read(premiumProvider).unlocked) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const PaywallScreen(feature: PremiumFeature.excel),
      ));
      return;
    }
    final years = {for (final m in months) m.year}.toList()..sort((a, b) => b.compareTo(a));
    final year = years.length == 1
        ? years.first
        : await showDialog<int>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Exportar que ano?'),
              children: [
                for (final y in years)
                  SimpleDialogOption(onPressed: () => Navigator.pop(ctx, y), child: Text('$y')),
              ],
            ),
          );
    if (year == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Exportar $year em Excel'),
        content: const Text(
          'O ficheiro tem o resumo anual (categorias por mês) e uma folha por mês com todos os '
          'movimentos. Sai da área cifrada do FINTRACK: partilhe só com quem confia.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Exportar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final chosen = [for (final m in months.reversed) if (m.year == year) m];
      final bytes = buildMonthsWorkbook(
        ledger: data.ledger,
        months: chosen,
        cycle: cycle,
        categoryName: (id) => data.category(id)?.name ?? '',
        accountName: (id) => data.account(id)?.name ?? '',
        today: _today,
        ownerName: ref.read(sessionProvider).profile?.name,
      );
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: xlsxMime)],
        fileNameOverrides: ['FINTRACK-$year.xlsx'],
        subject: 'FINTRACK $year',
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível gerar o Excel.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final finance = ref.watch(financeProvider);
    final session = ref.watch(sessionProvider);
    final cycle = session.monthCycle;
    final discreet = session.discreet;
    final main = session.profile?.mainCurrency ?? Currency.aoa;

    return Scaffold(
      appBar: AppBar(title: const Text('Resumos mensais')),
      body: finance.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Não foi possível ler os dados.')),
        data: (data) {
          final months = _months(data, cycle);
          return ListView(
            key: const Key('months-list'),
            padding: const EdgeInsets.fromLTRB(FtSpace.lg, FtSpace.sm, FtSpace.lg, FtSpace.xl),
            children: [
              TextPlate(
                padding: const EdgeInsets.all(FtSpace.md),
                child: Row(children: [
                  Icon(Icons.date_range_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: FtSpace.sm),
                  Expanded(child: Text(monthCycleSummary(cycle), style: theme.textTheme.bodyMedium)),
                  TextButton(onPressed: () => chooseMonthCycle(context, ref), child: const Text('Alterar')),
                ]),
              ),
              const SizedBox(height: FtSpace.sm),
              FilledButton.tonalIcon(
                key: const Key('export-year'),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Exportar o ano em Excel'),
                onPressed: _busy ? null : () => _exportYear(data, cycle, months),
              ),
              const SizedBox(height: FtSpace.md),
              for (final m in months)
                _MonthTile(
                  month: m,
                  report: PeriodReport.build(
                    data.ledger,
                    from: m.from,
                    to: m.to.isAfter(_today) && !m.from.isAfter(_today) ? _today : m.to,
                  ),
                  currency: main,
                  current: m.contains(_today),
                  discreet: discreet,
                  colors: colors,
                  muted: muted,
                  showRange: !cycle.isCalendar,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.month,
    required this.report,
    required this.currency,
    required this.current,
    required this.discreet,
    required this.colors,
    required this.muted,
    required this.showRange,
  });

  final FinancialMonth month;
  final PeriodReport report;
  final Currency currency;
  final bool current;
  final bool discreet;
  final FtColors colors;
  final TextStyle? muted;
  final bool showRange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = report.currencies.where((x) => x.currency == currency).firstOrNull ?? report.currencies.firstOrNull;
    String money(Money m) => amountText(m, discreet: discreet);
    final top = c?.expenseByCategory.firstOrNull;
    return TextPlate(
      margin: const EdgeInsets.only(bottom: FtSpace.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(FtRadius.lg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ReportScreen(initialMonth: month.from)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(FtSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(monthLabel(month), style: theme.textTheme.titleMedium)),
                if (current)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Em curso', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                  ),
                const Icon(Icons.chevron_right),
              ]),
              if (showRange) Text(monthRange(month), style: muted),
              const SizedBox(height: FtSpace.sm),
              if (c == null)
                Text('Sem contas nesta moeda.', style: muted)
              else ...[
                Row(children: [
                  Expanded(child: _Figure(label: 'Recebeu', value: money(c.income), color: colors.income)),
                  Expanded(child: _Figure(label: 'Gastou', value: money(c.expense), color: colors.expense)),
                  Expanded(
                    child: _Figure(
                      label: 'Saldo do mês',
                      value: money(c.net),
                      color: c.net.minor >= 0 ? colors.income : colors.expense,
                    ),
                  ),
                ]),
                if (top != null && c.expense.minor > 0) ...[
                  const SizedBox(height: FtSpace.xs),
                  Text(
                    'Maior gasto: ${_name(context, top.categoryId)} (${(top.total.minor * 100 / c.expense.minor).round()}%)',
                    style: muted,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _name(BuildContext context, String id) {
    final data = ProviderScope.containerOf(context).read(financeProvider).value;
    return data?.category(id)?.name ?? 'Outros';
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700, fontFeatures: ftAmountFeatures),
        ),
      ),
    ]);
  }
}

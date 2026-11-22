import 'dart:typed_data';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../security/session.dart';
import '../premium/paywall_screen.dart';
import '../premium/premium.dart';
import 'month_export.dart';
import 'pdf_report.dart';

/// Resumo de um mês financeiro: indicadores, categorias e exportação em PDF
/// e Excel. Segue o "mês financeiro" escolhido nas Definições.

const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, this.initialMonth});

  final DateTime? initialMonth;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  /// Mês financeiro mostrado (pelo nome: ano e mês).
  late DateTime _label;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(sessionProvider).monthCycle.of(widget.initialMonth ?? DateTime.now());
    _label = DateTime(p.year, p.month);
  }

  MonthCycle get _cycle => ref.read(sessionProvider).monthCycle;
  FinancialMonth get _period => _cycle.byLabel(_label.year, _label.month);

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Fim do período, sem passar de hoje no mês em curso.
  DateTime get _end {
    final p = _period;
    return p.to.isAfter(_today) && !p.from.isAfter(_today) ? _today : p.to;
  }

  bool get _isCurrentOrFuture => !_period.to.isBefore(_today);

  String get _fileStem => 'FINTRACK-${_label.year}-${_label.month.toString().padLeft(2, '0')}';

  Future<bool> _confirmExport(String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Exportar $what'),
        content: const Text(
          'O ficheiro sai da área cifrada do FINTRACK e fica legível por quem o '
          'receber. Partilhe apenas com quem confia.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Exportar')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _share(List<int> bytes, String mime, String name) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: mime)],
      fileNameOverrides: [name],
      subject: name,
    ));
  }

  Future<void> _exportPdf(FinanceData data, PeriodReport report) async {
    if (!ref.read(premiumProvider).unlocked) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const PaywallScreen(feature: PremiumFeature.pdf),
      ));
      return;
    }
    if (!await _confirmExport('PDF')) return;
    setState(() => _busy = true);
    try {
      final profile = ref.read(sessionProvider).profile;
      final bytes = await buildReportPdf(
        report: report,
        ownerName: profile?.name ?? 'FINTRACK',
        categoryName: (id) => data.category(id)?.name ?? '',
        accountName: (id) => data.account(id)?.name ?? '',
      );
      await _share(bytes, 'application/pdf', '$_fileStem.pdf');
    } catch (_) {
      _snack('Não foi possível gerar o PDF.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportExcel(FinanceData data) async {
    if (!ref.read(premiumProvider).unlocked) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const PaywallScreen(feature: PremiumFeature.excel),
      ));
      return;
    }
    if (!await _confirmExport('Excel')) return;
    setState(() => _busy = true);
    try {
      final bytes = buildMonthsWorkbook(
        ledger: data.ledger,
        months: [_period],
        cycle: _cycle,
        categoryName: (id) => data.category(id)?.name ?? '',
        accountName: (id) => data.account(id)?.name ?? '',
        today: _today,
        ownerName: ref.read(sessionProvider).profile?.name,
      );
      await _share(bytes, xlsxMime, '$_fileStem.xlsx');
    } catch (_) {
      _snack('Não foi possível gerar o Excel.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = ref.watch(financeProvider);
    final discreet = ref.watch(sessionProvider.select((s) => s.discreet));

    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios')),
      body: finance.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Não foi possível ler os dados.')),
        data: (data) {
          final period = _period;
          final report = PeriodReport.build(data.ledger, from: period.from, to: _end);
          String money(Money m) => amountText(m, discreet: discreet);
          return ListView(
            padding: const EdgeInsets.fromLTRB(FtSpace.lg, FtSpace.sm, FtSpace.lg, FtSpace.xl),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Mês anterior',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _label = DateTime(_label.year, _label.month - 1)),
                  ),
                  Expanded(
                    child: Column(children: [
                      Text(monthLabel(period), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                      if (!_cycle.isCalendar)
                        Text(
                          monthRange(period),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Mês seguinte',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _isCurrentOrFuture
                        ? null
                        : () => setState(() => _label = DateTime(_label.year, _label.month + 1)),
                  ),
                ],
              ),
              for (final c in report.currencies) ...[
                const SizedBox(height: FtSpace.md),
                _Panel(
                  title: 'Resumo · ${c.currency.code}',
                  children: [
                    _Line('Saldo inicial', money(c.opening)),
                    _Line('Entradas', money(c.income)),
                    _Line('Saídas', money(c.expense)),
                    _Line('Transferências recebidas', money(c.transfersIn)),
                    _Line('Transferências enviadas', money(c.transfersOut)),
                    const Divider(),
                    _Line('Saldo final', money(c.closing), strong: true),
                    _Line('Resultado do período', money(c.net), strong: true),
                    if (!c.pendingCommitments.isZero)
                      _Line('Compromissos pendentes', money(c.pendingCommitments)),
                  ],
                ),
                if (c.expenseByCategory.isNotEmpty) ...[
                  const SizedBox(height: FtSpace.md),
                  _Panel(
                    title: 'Saídas por categoria',
                    children: [
                      for (final x in c.expenseByCategory)
                        _CategoryBar(
                          label: data.category(x.categoryId)?.name ?? '?',
                          value: money(x.total),
                          fraction: c.expense.minor <= 0 ? 0 : x.total.minor / c.expense.minor,
                        ),
                    ],
                  ),
                ],
                if (c.incomeByCategory.isNotEmpty) ...[
                  const SizedBox(height: FtSpace.md),
                  _Panel(
                    title: 'Entradas por categoria',
                    children: [
                      for (final x in c.incomeByCategory)
                        _Line(data.category(x.categoryId)?.name ?? '?', money(x.total)),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: FtSpace.md),
              Text(
                '${report.movements.length} movimentos no período. '
                'Os valores são calculados pelo livro-razão.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: FtSpace.lg),
              FilledButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Exportar PDF'),
                onPressed: _busy ? null : () => _exportPdf(data, report),
              ),
              const SizedBox(height: FtSpace.sm),
              OutlinedButton.icon(
                key: const Key('export-excel'),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Exportar Excel'),
                onPressed: _busy ? null : () => _exportExcel(data),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(FtSpace.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(FtRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: FtSpace.sm),
          ...children,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (strong ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
        ?.copyWith(fontFeatures: ftAmountFeatures);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.label, required this.value, required this.fraction});

  final String label;
  final String value;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                '$value  ${(fraction * 100).round()}%',
                style: theme.textTheme.bodySmall?.copyWith(fontFeatures: ftAmountFeatures),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1),
              minHeight: 4,
              color: colors.expense,
              backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

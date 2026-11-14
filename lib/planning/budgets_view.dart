import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/plate.dart';
import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../security/session.dart';

Color budgetColor(BuildContext context, BudgetLevel level) {
  final theme = Theme.of(context);
  final colors = theme.extension<FtColors>()!;
  return switch (level) {
    BudgetLevel.ok || BudgetLevel.half => theme.colorScheme.primary,
    BudgetLevel.warning => colors.alert,
    BudgetLevel.exceeded => colors.expense,
  };
}

String budgetTitle(FinanceData data, Budget b) =>
    b.isGlobal ? 'Todas as despesas' : data.category(b.categoryId)?.name ?? '?';

/// Orçamentos do mês corrente, com alertas a 50%, 80% e 100%.
class BudgetsView extends StatelessWidget {
  const BudgetsView({super.key, required this.data, required this.discreet});

  final FinanceData data;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final budgets = [...data.budgets]..sort((a, b) => a.isGlobal ? -1 : b.isGlobal ? 1 : 0);
    if (budgets.isEmpty) {
      return TextPlate(
        padding: const EdgeInsets.all(FtSpace.lg),
        child: Text(
          'Defina quanto quer gastar por mês, no total ou por categoria. O FINTRACK '
          'avisa aos 50%, 80% e 100%.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: FtSpace.sm),
          child: Align(alignment: Alignment.centerLeft, child: PlateLabel(child: Text(
            '${monthName(month.month)} de ${month.year}'.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              letterSpacing: 1.3,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ))),
        ),
        for (final b in budgets)
          BudgetTile(
            data: data,
            status: BudgetEngine.status(data.ledger, b, month: month, today: now),
            discreet: discreet,
          ),
      ],
    );
  }
}

class BudgetTile extends StatelessWidget {
  const BudgetTile({
    super.key,
    required this.data,
    required this.status,
    required this.discreet,
    this.compact = false,
  });

  final FinanceData data;
  final BudgetStatus status;
  final bool discreet;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final b = status.budget;
    final color = budgetColor(context, status.level);
    final category = data.category(b.categoryId);
    String money(Money m) => amountText(m, discreet: discreet);
    final remaining = status.remaining;
    final projected = status.projected;

    return InkWell(
      borderRadius: BorderRadius.circular(FtRadius.md),
      onTap: compact
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => BudgetFormScreen(data: data, editing: b),
              )),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FtSpace.sm, horizontal: FtSpace.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(b.isGlobal ? Icons.donut_large : categoryIcon(category?.icon ?? ''), size: 18, color: color),
                const SizedBox(width: FtSpace.sm),
                Expanded(child: Text(budgetTitle(data, b), style: theme.textTheme.titleSmall)),
                Text(
                  discreet ? '••• %' : '${status.percent}%',
                  style: theme.textTheme.labelLarge?.copyWith(color: color, fontFeatures: ftAmountFeatures),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (status.percent / 100).clamp(0, 1).toDouble(),
                minHeight: compact ? 4 : 6,
                color: color,
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              remaining.isNegative
                  ? 'Ultrapassado em ${money(-remaining)} · gasto ${money(status.spent)} de ${money(status.limit)}'
                  : 'Restam ${money(remaining)} · gasto ${money(status.spent)} de ${money(status.limit)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: remaining.isNegative ? colors.expense : theme.colorScheme.onSurfaceVariant,
                fontFeatures: ftAmountFeatures,
              ),
            ),
            if (!compact && projected != null && !discreet && projected.minor > status.limit.minor)
              Text(
                'Estimativa: ao ritmo atual, chega a ${projected.format()} no fim do mês.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.estimate,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Criar ou editar um orçamento mensal.
class BudgetFormScreen extends ConsumerStatefulWidget {
  const BudgetFormScreen({super.key, required this.data, this.editing});

  final FinanceData data;
  final Budget? editing;

  @override
  ConsumerState<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class _BudgetFormScreenState extends ConsumerState<BudgetFormScreen> {
  late String? _categoryId = widget.editing?.categoryId;
  late bool _carry = widget.editing?.carryOver ?? false;
  late final _amount = TextEditingController(
    text: widget.editing?.amount.format(withSymbol: false) ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Currency get _currency =>
      widget.editing?.amount.currency ?? ref.read(sessionProvider).profile?.mainCurrency ?? Currency.aoa;

  Future<void> _save() async {
    Money amount;
    try {
      amount = Money.parse(_amount.text, _currency);
      if (amount.minor <= 0) throw const FormatException();
    } on FormatException {
      setState(() => _error = 'Indique um valor maior que zero. Exemplo: 150 000');
      return;
    }
    final existing = widget.editing ??
        widget.data.budgets
            .where((b) => b.categoryId == _categoryId && b.amount.currency == _currency)
            .firstOrNull;
    final now = DateTime.now();
    final budget = existing?.copyWith(amount: amount, carryOver: _carry) ??
        Budget(
          id: newId(),
          categoryId: _categoryId,
          amount: amount,
          startMonth: DateTime(now.year, now.month),
          carryOver: _carry,
          createdAt: now,
        );
    final store = ref.read(sessionProvider.notifier).store;
    if (store == null) return;
    await store.saveBudget(budget);
    ref.invalidate(financeProvider);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final b = widget.editing;
    final store = ref.read(sessionProvider.notifier).store;
    if (b == null || store == null) return;
    await store.deleteBudget(b.id);
    ref.invalidate(financeProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.editing;
    final categories = [
      for (final c in widget.data.categories)
        if (!c.archived && c.kind == CategoryKind.expense) c,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(editing == null ? 'Novo orçamento' : 'Editar orçamento')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FtSpace.lg),
          children: [
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Aplica-se a', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todas as despesas (global)')),
                for (final c in categories) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: editing != null ? null : (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: FtSpace.md),
            TextField(
              key: const Key('budget-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: theme.textTheme.headlineSmall?.copyWith(fontFeatures: ftAmountFeatures),
              decoration: InputDecoration(
                labelText: 'Valor por mês',
                suffixText: _currency.symbol,
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Transportar o saldo para o mês seguinte'),
              subtitle: const Text('O que sobrar (ou faltar) passa para o mês seguinte.'),
              value: _carry,
              onChanged: (v) => setState(() => _carry = v),
            ),
            const SizedBox(height: FtSpace.sm),
            Text(
              'Vale todos os meses até o alterar. Transferências entre as suas contas nunca contam como despesa.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: FtSpace.lg),
            FilledButton(onPressed: _save, child: const Text('Guardar orçamento')),
            if (editing != null) ...[
              const SizedBox(height: FtSpace.sm),
              OutlinedButton(onPressed: _delete, child: const Text('Remover orçamento')),
            ],
          ],
        ),
      ),
    );
  }
}

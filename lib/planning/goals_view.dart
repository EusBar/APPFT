import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/plate.dart';
import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../security/session.dart';

/// Objetivos: progresso, quanto falta e quanto juntar por mês.
class GoalsView extends StatelessWidget {
  const GoalsView({super.key, required this.data, required this.discreet});

  final FinanceData data;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goals = [for (final g in data.goals) if (!g.archived) g];
    if (goals.isEmpty) {
      return TextPlate(
        padding: const EdgeInsets.all(FtSpace.lg),
        child: Text(
          'Crie um objetivo (viagem, carro, reserva de emergência). Associe uma conta de '
          'poupança para o progresso ser automático, ou registe as contribuições à mão.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    final now = DateTime.now();
    return Column(
      children: [
        for (final g in goals)
          _GoalCard(
            data: data,
            progress: GoalEngine.progress(data.ledger, g, data.contributions, today: now),
            discreet: discreet,
          ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.data, required this.progress, required this.discreet});

  final FinanceData data;
  final GoalProgress progress;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final g = progress.goal;
    String money(Money m) => amountText(m, discreet: discreet);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final color = progress.done ? colors.income : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: FtSpace.md),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(FtRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(FtRadius.lg),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (_) => _GoalSheet(data: data, progress: progress),
          ),
          child: Padding(
            padding: const EdgeInsets.all(FtSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(g.name, style: theme.textTheme.titleMedium)),
                    if (progress.milestone > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: FtSpace.sm, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(FtRadius.lg),
                        ),
                        child: Text(
                          progress.done ? 'Concluído ✓' : 'Marco ${progress.milestone}%',
                          style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: FtSpace.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (progress.percent / 100).clamp(0, 1),
                    minHeight: 8,
                    color: color,
                    backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                ),
                const SizedBox(height: FtSpace.sm),
                Text(
                  '${money(progress.saved)} de ${money(g.target)} · ${discreet ? '•••' : '${progress.percent}%'}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: ftAmountFeatures),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (!progress.done) 'Faltam ${money(progress.remaining)}',
                    if (g.deadline != null) 'até ${dayLabel(g.deadline!)}',
                    if (progress.monthlyNeeded != null) '${money(progress.monthlyNeeded!)}/mês',
                    g.isReserved
                        ? 'reservado em ${data.account(g.accountId)?.name ?? '?'}'
                        : 'planeado',
                  ].join(' · '),
                  style: muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalSheet extends ConsumerWidget {
  const _GoalSheet({required this.data, required this.progress});

  final FinanceData data;
  final GoalProgress progress;

  Future<void> _contribute(BuildContext context, WidgetRef ref, {required bool add}) async {
    final g = progress.goal;
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(add ? 'Juntar ao objetivo' : 'Retirar do objetivo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: g.target.currency.symbol, hintText: '0,00'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Registar')),
        ],
      ),
    );
    if (value == null || !context.mounted) return;
    Money amount;
    try {
      amount = Money.parse(value, g.target.currency);
      if (amount.minor <= 0) return;
    } on FormatException {
      return;
    }
    final store = ref.read(sessionProvider.notifier).store;
    if (store == null) return;
    final now = DateTime.now();
    await store.addGoalContribution(GoalContribution(
      id: newId(),
      goalId: g.id,
      amount: add ? amount : -amount,
      date: now,
      createdAt: now,
    ));
    ref.invalidate(financeProvider);
    if (!context.mounted) return;
    final before = progress.milestone;
    final after = GoalEngine.progress(
      data.ledger,
      g,
      [...data.contributions, GoalContribution(id: '', goalId: g.id, amount: add ? amount : -amount, date: now, createdAt: now)],
      today: now,
    ).milestone;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text(after > before ? 'Parabéns: chegou aos $after% de "${g.name}" 🎉' : 'Contribuição registada.'),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final g = progress.goal;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FtSpace.lg, 0, FtSpace.lg, FtSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(g.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: FtSpace.sm),
            Text(
              g.isReserved
                  ? 'O progresso é o saldo da conta "${data.account(g.accountId)?.name ?? '?'}". '
                      'Para juntar, faça uma transferência para essa conta (não conta como despesa).'
                  : 'Objetivo planeado: registe aqui o que vai juntando. Não mexe nos saldos das contas.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: FtSpace.lg),
            if (!g.isReserved) ...[
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Juntar'),
                onPressed: () => _contribute(context, ref, add: true),
              ),
              const SizedBox(height: FtSpace.sm),
              OutlinedButton.icon(
                icon: const Icon(Icons.remove),
                label: const Text('Retirar'),
                onPressed: () => _contribute(context, ref, add: false),
              ),
              const SizedBox(height: FtSpace.sm),
            ],
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar'),
              onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute<void>(builder: (_) => GoalFormScreen(data: data, editing: g)));
              },
            ),
            const SizedBox(height: FtSpace.sm),
            TextButton(
              onPressed: () async {
                final store = ref.read(sessionProvider.notifier).store;
                if (store == null) return;
                await store.saveGoal(g.copyWith(archived: true));
                ref.invalidate(financeProvider);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Arquivar objetivo'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Criar ou editar um objetivo.
class GoalFormScreen extends ConsumerStatefulWidget {
  const GoalFormScreen({super.key, required this.data, this.editing});

  final FinanceData data;
  final Goal? editing;

  @override
  ConsumerState<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends ConsumerState<GoalFormScreen> {
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late final _target = TextEditingController(text: widget.editing?.target.format(withSymbol: false) ?? '');
  late DateTime? _deadline = widget.editing?.deadline;
  late String? _accountId = widget.editing?.accountId;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Currency get _currency =>
      widget.data.account(_accountId)?.currency ??
      widget.editing?.target.currency ??
      ref.read(sessionProvider).profile?.mainCurrency ??
      Currency.aoa;

  Future<void> _save() async {
    final name = NameRules.clean(_name.text);
    Money? target;
    try {
      target = Money.parse(_target.text, _currency);
    } on FormatException {
      target = null;
    }
    if (name == null || target == null || target.minor <= 0) {
      setState(() => _error = 'Indique o nome e o valor pretendido.');
      return;
    }
    final e = widget.editing;
    final goal = e == null
        ? Goal(
            id: newId(),
            name: name,
            target: target,
            deadline: _deadline,
            accountId: _accountId,
            createdAt: DateTime.now(),
          )
        : e.copyWith(name: name, target: target, deadline: _deadline, clearDeadline: _deadline == null);
    final store = ref.read(sessionProvider.notifier).store;
    if (store == null) return;
    await store.saveGoal(goal);
    ref.invalidate(financeProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.editing;
    return Scaffold(
      appBar: AppBar(title: Text(editing == null ? 'Novo objetivo' : 'Editar objetivo')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FtSpace.lg),
          children: [
            TextField(
              key: const Key('goal-name'),
              controller: _name,
              maxLength: NameRules.maxLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Ex.: Viagem a Benguela',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FtSpace.sm),
            TextField(
              key: const Key('goal-target'),
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Valor pretendido',
                suffixText: _currency.symbol,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FtSpace.md),
            DropdownButtonFormField<String?>(
              initialValue: _accountId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Dinheiro reservado em',
                helperText: 'Com conta, o progresso é o saldo dela. Sem conta, regista à mão.',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Nenhuma conta (planeado)')),
                for (final a in widget.data.openAccounts)
                  DropdownMenuItem<String?>(value: a.id, child: Text('${a.name} · ${accountTypeLabel(a.type)}')),
              ],
              onChanged: editing != null ? null : (v) => setState(() => _accountId = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Prazo (opcional)'),
              subtitle: Text(_deadline == null ? 'Sem prazo' : dayLabel(_deadline!)),
              trailing: _deadline == null
                  ? null
                  : IconButton(
                      tooltip: 'Sem prazo',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _deadline = null),
                    ),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _deadline ?? DateTime(now.year, now.month + 6, now.day),
                  firstDate: now,
                  lastDate: DateTime(now.year + 30),
                );
                if (picked != null) setState(() => _deadline = picked);
              },
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: FtSpace.lg),
            FilledButton(onPressed: _save, child: const Text('Guardar objetivo')),
          ],
        ),
      ),
    );
  }
}

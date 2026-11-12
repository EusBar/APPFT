import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../security/session.dart';
import 'finance_data.dart';
import 'movement_form_screen.dart';

/// Linha de um movimento: ícone, descrição, conta e valor com sinal e cor.
class MovementTile extends StatelessWidget {
  const MovementTile({
    super.key,
    required this.movement,
    required this.data,
    required this.discreet,
    this.cancelled = false,
  });

  final Movement movement;
  final FinanceData data;
  final bool discreet;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final m = movement;
    final category = data.category(m.categoryId);
    final from = data.account(m.accountId);
    final to = data.account(m.toAccountId);

    final (color, sign, icon) = switch (m.kind) {
      MovementKind.income => (colors.income, '+', categoryIcon(category?.icon ?? '')),
      MovementKind.expense => (colors.expense, '−', categoryIcon(category?.icon ?? '')),
      MovementKind.transfer => (colors.transfer, '', Icons.swap_horiz),
    };
    final title = m.description.isNotEmpty
        ? m.description
        : m.kind == MovementKind.transfer
            ? 'Transferência'
            : category?.name ?? movementKindLabel(m.kind);
    final subtitle = m.kind == MovementKind.transfer
        ? '${from?.name ?? '?'} → ${to?.name ?? '?'}'
        : [if (m.description.isNotEmpty && category != null) category.name, from?.name ?? '?']
            .join(' · ');
    final amount = discreet ? '••••••' : '$sign${m.amount.format()}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: FtSpace.xs),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.16),
        foregroundColor: color,
        child: Icon(icon, size: 20),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
      ),
      subtitle: Text(
        cancelled ? 'Anulado · $subtitle' : subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        amount,
        semanticsLabel: discreet ? 'Valor oculto' : null,
        style: theme.textTheme.titleSmall?.copyWith(
          fontFeatures: ftAmountFeatures,
          color: cancelled ? theme.colorScheme.onSurfaceVariant : color,
          decoration: cancelled ? TextDecoration.lineThrough : null,
        ),
      ),
      onTap: () => showMovementDetails(context, m, data),
    );
  }
}

/// Detalhe de um movimento, com Corrigir e Anular.
Future<void> showMovementDetails(BuildContext context, Movement m, FinanceData data) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _MovementDetails(movement: m, data: data),
  );
}

class _MovementDetails extends ConsumerWidget {
  const _MovementDetails({required this.movement, required this.data});

  final Movement movement;
  final FinanceData data;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anular este movimento?'),
        content: const Text(
          'O movimento não é apagado: fica registado um estorno que anula o '
          'seu efeito nos saldos. O histórico mantém os dois.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final store = ref.read(sessionProvider.notifier).store;
    if (store == null) return;
    final issue = await LedgerWriter(store, data).cancel(movement);
    ref.invalidate(financeProvider);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(issue == null ? 'Movimento anulado.' : movementIssueMessage(issue))),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final m = movement;
    final discreet = ref.watch(sessionProvider.select((s) => s.discreet));
    final cancelled = data.ledger.isReversed(m.id);
    final category = data.category(m.categoryId);
    String money(Money v) => discreet ? '••••••' : v.format();

    final rows = <(String, String)>[
      ('Tipo', movementKindLabel(m.kind)),
      (m.kind == MovementKind.transfer ? 'Valor enviado' : 'Valor', money(m.amount)),
      if (m.toAmount != null && m.toAmount!.currency != m.amount.currency)
        ('Valor recebido', money(m.toAmount!)),
      if (m.kind == MovementKind.transfer) ...[
        ('De', data.account(m.accountId)?.name ?? '?'),
        ('Para', data.account(m.toAccountId)?.name ?? '?'),
      ] else ...[
        ('Conta', data.account(m.accountId)?.name ?? '?'),
        ('Categoria', category?.name ?? '?'),
      ],
      ('Data', dayLabel(m.date)),
      if (m.description.isNotEmpty) ('Descrição', m.description),
      if (m.note.isNotEmpty) ('Observações', m.note),
      if (m.replaces != null) ('Histórico', 'Corrige um movimento anterior'),
      if (cancelled) ('Estado', 'Anulado por estorno'),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FtSpace.lg, 0, FtSpace.lg, FtSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Movimento', style: theme.textTheme.titleLarge),
            const SizedBox(height: FtSpace.md),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: FtSpace.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(fontFeatures: ftAmountFeatures),
                      ),
                    ),
                  ],
                ),
              ),
            if (!cancelled) ...[
              const SizedBox(height: FtSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.undo),
                      label: const Text('Anular'),
                      onPressed: () => _cancel(context, ref),
                    ),
                  ),
                  const SizedBox(width: FtSpace.md),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Corrigir'),
                      onPressed: () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        nav.push(MaterialPageRoute<void>(
                          builder: (_) => MovementFormScreen(data: data, editing: m),
                        ));
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

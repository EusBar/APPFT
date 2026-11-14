import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/plate.dart';
import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../security/session.dart';
import 'commitment_form_screen.dart';

/// Separador Planear: compromissos em atraso, pendentes e concluídos.
class CommitmentsView extends StatelessWidget {
  const CommitmentsView({super.key, required this.data, required this.discreet});

  final FinanceData data;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledger = data.ledger;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final pending = ledger.pending();
    final overdue = [for (final c in pending) if (c.dueDate.isBefore(today)) c];
    final upcoming = [for (final c in pending) if (!c.dueDate.isBefore(today)) c];
    final done = [
      for (final c in data.ledger.commitments)
        if (ledger.statusOf(c) != CommitmentStatus.pending) c,
    ]..sort((a, b) => b.dueDate.compareTo(a.dueDate));

    Widget header(String text) => Padding(
          padding: const EdgeInsets.only(top: FtSpace.lg, bottom: FtSpace.xs),
          child: Align(alignment: Alignment.centerLeft, child: PlateLabel(child: Text(
            text.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              letterSpacing: 1.3,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ))),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending.isEmpty && done.isEmpty)
          TextPlate(
            padding: const EdgeInsets.all(FtSpace.lg),
            child: Text(
              'Sem compromissos. Registe pagamentos previstos (renda, propinas, '
              'prestações) para o saldo disponível refletir o que já está prometido.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        if (overdue.isNotEmpty) ...[
          header('Em atraso'),
          TextPlate(child: Column(children: [
            for (final c in overdue) CommitmentTile(commitment: c, data: data, discreet: discreet),
          ])),
        ],
        if (upcoming.isNotEmpty) ...[
          header('Pendentes'),
          TextPlate(child: Column(children: [
            for (final c in upcoming) CommitmentTile(commitment: c, data: data, discreet: discreet),
          ])),
        ],
        if (done.isNotEmpty) ...[
          header('Concluídos'),
          TextPlate(child: Column(children: [
            for (final c in done.take(20)) CommitmentTile(commitment: c, data: data, discreet: discreet),
          ])),
        ],
      ],
    );
  }
}

class CommitmentTile extends StatelessWidget {
  const CommitmentTile({
    super.key,
    required this.commitment,
    required this.data,
    required this.discreet,
  });

  final Commitment commitment;
  final FinanceData data;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final c = commitment;
    final status = data.ledger.statusOf(c);
    final now = DateTime.now();
    final overdue = status == CommitmentStatus.pending &&
        c.dueDate.isBefore(DateTime(now.year, now.month, now.day));
    final color = switch (status) {
      CommitmentStatus.pending => overdue ? colors.alert : colors.commitment,
      CommitmentStatus.paid => colors.income,
      CommitmentStatus.cancelled => theme.colorScheme.onSurfaceVariant,
    };
    final statusText = switch (status) {
      CommitmentStatus.pending => overdue ? 'Em atraso · ${dayLabel(c.dueDate)}' : dayLabel(c.dueDate),
      CommitmentStatus.paid => 'Pago',
      CommitmentStatus.cancelled => 'Cancelado',
    };
    final category = data.category(c.categoryId);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: FtSpace.xs),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.16),
        foregroundColor: color,
        child: Icon(
          status == CommitmentStatus.paid
              ? Icons.check
              : categoryIcon(category?.icon ?? ''),
          size: 20,
        ),
      ),
      title: Text(
        c.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: status == CommitmentStatus.cancelled
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(
        '$statusText${c.recurrence == Recurrence.none ? '' : ' · ↻ ${recurrenceLabel(c.recurrence).toLowerCase()}'}'
        ' · ${data.account(c.accountId)?.name ?? '?'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: overdue ? TextStyle(color: colors.alert) : null,
      ),
      trailing: Text(
        discreet ? '••••••' : c.amount.format(),
        style: theme.textTheme.titleSmall?.copyWith(fontFeatures: ftAmountFeatures, color: color),
      ),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _CommitmentSheet(commitment: c, data: data),
      ),
    );
  }
}

class _CommitmentSheet extends ConsumerWidget {
  const _CommitmentSheet({required this.commitment, required this.data});

  final Commitment commitment;
  final FinanceData data;

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    final c = commitment;
    final account = data.account(c.accountId);
    final now = DateTime.now();
    var date = DateTime(now.year, now.month, now.day);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Registar pagamento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vai ser registada uma saída de ${c.amount.format()} na conta '
                '${account?.name ?? '?'}, e o compromisso deixa de reduzir o disponível.',
              ),
              const SizedBox(height: FtSpace.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Data do pagamento'),
                subtitle: Text(dayLabel(date)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: account?.startDate ?? DateTime(now.year - 1),
                    lastDate: now,
                  );
                  if (picked != null) setState(() => date = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmar pagamento'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final store = ref.read(sessionProvider.notifier).store;
    if (store == null) return;
    final issue = await LedgerWriter(store, data).payCommitment(c, date: date);
    ref.invalidate(financeProvider);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text(issue == null ? 'Pagamento registado.' : movementIssueMessage(issue)),
    ));
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final recurring = commitment.recurrence != Recurrence.none;
    // null = manter; true = só esta (série continua); false = cancelar/terminar.
    final choice = await showDialog<bool?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(recurring ? 'Cancelar compromisso recorrente' : 'Cancelar este compromisso?'),
        content: Text(recurring
            ? 'Pode saltar só esta ocorrência (o FINTRACK prepara a seguinte) ou terminar a série.'
            : 'Deixa de reduzir o saldo disponível. Não é registada nenhuma saída.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Manter')),
          if (recurring)
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Saltar esta')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(recurring ? 'Terminar a série' : 'Cancelar compromisso'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    final store = ref.read(sessionProvider.notifier).store;
    if (store == null) return;
    final issue = await LedgerWriter(store, data).cancelCommitment(commitment, continueSeries: choice);
    ref.invalidate(financeProvider);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text(issue == null ? 'Compromisso cancelado.' : movementIssueMessage(issue)),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = commitment;
    final ledger = data.ledger;
    final status = ledger.statusOf(c);
    final discreet = ref.watch(sessionProvider.select((s) => s.discreet));
    final payment = ledger.paymentOf(c);
    final rows = <(String, String)>[
      ('Valor', discreet ? '••••••' : c.amount.format()),
      ('Data prevista', dayLabel(c.dueDate)),
      if (c.recurrence != Recurrence.none) ('Repetição', recurrenceLabel(c.recurrence)),
      ('Conta', data.account(c.accountId)?.name ?? '?'),
      ('Categoria', data.category(c.categoryId)?.name ?? '?'),
      ('Estado', switch (status) {
        CommitmentStatus.pending => 'Pendente',
        CommitmentStatus.paid => 'Pago',
        CommitmentStatus.cancelled => 'Cancelado',
      }),
      if (payment != null) ('Pago em', dayLabel(payment.date)),
      if (c.note.isNotEmpty) ('Observações', c.note),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FtSpace.lg, 0, FtSpace.lg, FtSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(c.description, style: theme.textTheme.titleLarge),
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
                      child: Text(value, style: const TextStyle(fontFeatures: ftAmountFeatures)),
                    ),
                  ],
                ),
              ),
            if (status == CommitmentStatus.pending) ...[
              const SizedBox(height: FtSpace.lg),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Marcar como pago'),
                onPressed: () => _pay(context, ref),
              ),
              const SizedBox(height: FtSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar'),
                      onPressed: () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        nav.push(MaterialPageRoute<void>(
                          builder: (_) => CommitmentFormScreen(data: data, editing: c),
                        ));
                      },
                    ),
                  ),
                  const SizedBox(width: FtSpace.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close),
                      label: const Text('Cancelar'),
                      onPressed: () => _cancel(context, ref),
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

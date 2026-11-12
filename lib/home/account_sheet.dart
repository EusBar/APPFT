import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../security/session.dart';
import 'account_form.dart';

/// Detalhe de uma conta com Editar, Arquivar/Reativar e Apagar.
///
/// Regras (do motor): apagar só sem movimentos nem compromissos; o saldo
/// inicial só se corrige sem movimentos; com histórico, a conta arquiva-se.
Future<void> showAccountSheet(BuildContext context, Account account, FinanceData data) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AccountSheet(account: account, data: data),
  );
}

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet({required this.account, required this.data});

  final Account account;
  final FinanceData data;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(LocalStore store) action,
    String done,
  ) async {
    final store = ref.read(sessionProvider.notifier).store;
    if (store == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await action(store);
      ref.invalidate(financeProvider);
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Não foi possível concluir.')));
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ledger = data.ledger;
    final a = account;
    final discreet = ref.watch(sessionProvider.select((s) => s.discreet));
    final canDelete = ledger.canDelete(a.id);
    final canArchive = ledger.canArchive(a.id);
    final hasHistory = ledger.hasMovements(a.id) || ledger.hasCommitments(a.id);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final rows = <(String, String)>[
      ('Tipo', accountTypeLabel(a.type)),
      if (a.institution != null) ('Instituição', a.institution!),
      ('Moeda', '${a.currency.code} · ${currencyName(a.currency)}'),
      ('Saldo inicial', discreet ? '••••••' : a.openingBalance.format()),
      ('Saldo atual', discreet ? '••••••' : ledger.balanceOf(a.id).format()),
      ('Desde', dayLabel(a.startDate)),
      ('Saldo disponível', a.includeInAvailable ? 'Incluída' : 'Fora do disponível'),
      if (a.archived) ('Estado', 'Arquivada'),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FtSpace.lg, 0, FtSpace.lg, FtSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(a.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: FtSpace.md),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: FtSpace.xs),
                child: Row(
                  children: [
                    SizedBox(width: 130, child: Text(label, style: muted)),
                    Expanded(child: Text(value, style: const TextStyle(fontFeatures: ftAmountFeatures))),
                  ],
                ),
              ),
            const SizedBox(height: FtSpace.lg),
            if (!a.archived)
              FilledButton.tonalIcon(
                icon: const Icon(Icons.edit_outlined),
                label: Text(ledger.canEditOpening(a.id) ? 'Editar ou corrigir saldo inicial' : 'Editar'),
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute<void>(
                    builder: (_) => EditAccountScreen(account: a, openingEditable: ledger.canEditOpening(a.id)),
                  ));
                },
              ),
            const SizedBox(height: FtSpace.sm),
            if (a.archived)
              OutlinedButton.icon(
                icon: const Icon(Icons.unarchive_outlined),
                label: const Text('Reativar conta'),
                onPressed: () => _run(
                  context,
                  ref,
                  (store) => store.updateAccount(a.copyWith(archived: false)),
                  'Conta reativada.',
                ),
              )
            else if (hasHistory)
              OutlinedButton.icon(
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Arquivar conta'),
                onPressed: !canArchive
                    ? null
                    : () async {
                        if (!await _confirm(
                          context,
                          'Arquivar esta conta?',
                          'Deixa de contar nos saldos e de aparecer nas listas. O histórico '
                              'fica guardado e pode reativá-la quando quiser.',
                          'Arquivar',
                        )) {
                          return;
                        }
                        if (!context.mounted) return;
                        await _run(
                          context,
                          ref,
                          (store) => store.updateAccount(a.copyWith(archived: true)),
                          'Conta arquivada.',
                        );
                      },
              ),
            if (canDelete) ...[
              const SizedBox(height: FtSpace.sm),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Apagar conta'),
                onPressed: () async {
                  if (!await _confirm(
                    context,
                    'Apagar esta conta?',
                    'A conta não tem movimentos nem compromissos, por isso pode ser apagada '
                        'sem alterar o seu histórico.',
                    'Apagar',
                  )) {
                    return;
                  }
                  if (!context.mounted) return;
                  await _run(context, ref, (store) => store.deleteAccount(a.id), 'Conta apagada.');
                },
              ),
            ],
            const SizedBox(height: FtSpace.md),
            Text(
              hasHistory
                  ? 'Esta conta tem histórico: não pode ser apagada nem ter o saldo inicial '
                      'alterado, para os saldos e relatórios continuarem certos.'
                      '${!canArchive && !a.archived ? ' Para arquivar, resolva primeiro os compromissos pendentes desta conta.' : ''}'
                  : canDelete
                      ? 'Sem movimentos: pode corrigir o saldo inicial ou apagar a conta.'
                      : 'É a única conta ativa: crie outra antes de a apagar.',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}

class EditAccountScreen extends ConsumerWidget {
  const EditAccountScreen({super.key, required this.account, required this.openingEditable});

  final Account account;
  final bool openingEditable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar conta')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FtSpace.lg),
          children: [
            AccountForm(
              initial: account,
              openingEditable: openingEditable,
              defaultCurrency: account.currency,
              submitLabel: 'Guardar alterações',
              onSubmit: (updated) async {
                final store = ref.read(sessionProvider.notifier).store;
                if (store == null) return;
                await store.updateAccount(updated);
                ref.invalidate(financeProvider);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

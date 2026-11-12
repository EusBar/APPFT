import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../security/session.dart';
import '../settings/settings_screen.dart';
import 'account_form.dart';

/// Contas da base local. Recarrega quando a sessão muda ou após `invalidate`.
final accountsProvider = FutureProvider.autoDispose<List<Account>>((ref) async {
  ref.watch(sessionProvider.select((s) => s.status));
  final store = ref.read(sessionProvider.notifier).store;
  if (store == null) return const [];
  return store.accounts();
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final controller = ref.read(sessionProvider.notifier);
    final accounts = ref.watch(accountsProvider);
    final profile = session.profile;

    return Scaffold(
      appBar: AppBar(
        title: Text(profile == null ? 'FINTRACK' : 'Olá, ${profile.name.split(' ').first}'),
        actions: [
          IconButton(
            tooltip: session.discreet ? 'Mostrar valores' : 'Ocultar valores',
            icon: Icon(session.discreet ? Icons.visibility_off : Icons.visibility),
            onPressed: controller.toggleDiscreet,
          ),
          IconButton(
            tooltip: 'Definições',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Bloquear',
            icon: const Icon(Icons.lock_outline),
            onPressed: controller.lock,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: profile == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NewAccountScreen(defaultCurrency: profile.mainCurrency),
                  ),
                ),
        icon: const Icon(Icons.add),
        label: const Text('Nova conta'),
      ),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Não foi possível ler as contas.')),
        data: (list) => _HomeBody(
          accounts: list,
          discreet: session.discreet,
          onToggleDiscreet: controller.toggleDiscreet,
        ),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.accounts,
    required this.discreet,
    required this.onToggleDiscreet,
  });

  final List<Account> accounts;
  final bool discreet;
  final VoidCallback onToggleDiscreet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = Balances.byCurrency(accounts, availableOnly: true);
    final total = Balances.byCurrency(accounts);

    return ListView(
      padding: const EdgeInsets.fromLTRB(FtSpace.lg, FtSpace.md, FtSpace.lg, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(FtSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saldo disponível', style: theme.textTheme.labelLarge),
                const SizedBox(height: FtSpace.xs),
                GestureDetector(
                  onDoubleTap: onToggleDiscreet,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (available.isEmpty)
                        _Amount(Money.zero(accounts.isEmpty ? Currency.aoa : accounts.first.currency),
                            discreet: discreet, large: true),
                      for (final m in available.values) _Amount(m, discreet: discreet, large: true),
                    ],
                  ),
                ),
                if (total.length != available.length ||
                    total.entries.any((e) => available[e.key] != e.value)) ...[
                  const SizedBox(height: FtSpace.sm),
                  Text('Total em todas as contas', style: theme.textTheme.labelMedium),
                  for (final m in total.values) _Amount(m, discreet: discreet),
                ],
                const SizedBox(height: FtSpace.sm),
                Text(
                  'Ainda sem movimentos: os saldos são os saldos iniciais.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: FtSpace.lg),
        Text('Contas', style: theme.textTheme.titleMedium),
        const SizedBox(height: FtSpace.sm),
        for (final a in accounts.where((a) => !a.archived))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Icon(accountTypeIcon(a.type))),
            title: Text(a.name),
            subtitle: Text([
              accountTypeLabel(a.type),
              if (a.institution != null) a.institution!,
              if (!a.includeInAvailable) 'fora do disponível',
            ].join(' · ')),
            trailing: Text(
              amountText(a.openingBalance, discreet: discreet),
              style: theme.textTheme.titleSmall?.copyWith(fontFeatures: ftAmountFeatures),
            ),
          ),
      ],
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount(this.money, {required this.discreet, this.large = false});

  final Money money;
  final bool discreet;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = large ? theme.textTheme.headlineMedium : theme.textTheme.titleMedium;
    return Text(
      amountText(money, discreet: discreet),
      semanticsLabel: discreet ? 'Valor oculto' : null,
      style: style?.copyWith(fontFeatures: ftAmountFeatures, fontWeight: FontWeight.w600),
    );
  }
}

class NewAccountScreen extends ConsumerWidget {
  const NewAccountScreen({super.key, required this.defaultCurrency});

  final Currency defaultCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nova conta')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FtSpace.lg),
          children: [
            AccountForm(
              defaultCurrency: defaultCurrency,
              submitLabel: 'Guardar conta',
              onSubmit: (account) async {
                final store = ref.read(sessionProvider.notifier).store;
                if (store == null) return;
                await store.addAccount(account);
                ref.invalidate(accountsProvider);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/backdrop.dart';
import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../finance/movement_form_screen.dart';
import '../finance/movement_tile.dart';
import '../finance/movements_screen.dart';
import '../security/session.dart';
import '../settings/settings_screen.dart';
import 'account_form.dart';

/// Ecrã principal com navegação inferior: Início, Movimentos, Contas.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final controller = ref.read(sessionProvider.notifier);
    final finance = ref.watch(financeProvider);
    final profile = session.profile;
    final data = finance.valueOrNull;

    final title = switch (_tab) {
      0 => profile == null ? 'FINTRACK' : 'Olá, ${profile.name.split(' ').first}',
      1 => 'Movimentos',
      _ => 'Contas',
    };

    return FtBackdrop(
      image: FtImage.analytics,
      strength: FtBackdropStrength.subtle,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(title),
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
        floatingActionButton: data == null
            ? null
            : _tab == 2
                ? FloatingActionButton.extended(
                    heroTag: 'fab',
                    onPressed: profile == null
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) =>
                                  NewAccountScreen(defaultCurrency: profile.mainCurrency),
                            )),
                    icon: const Icon(Icons.add),
                    label: const Text('Nova conta'),
                  )
                : FloatingActionButton.extended(
                    heroTag: 'fab',
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => MovementFormScreen(data: data),
                    )),
                    icon: const Icon(Icons.add),
                    label: const Text('Movimento'),
                  ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Início',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Movimentos',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'Contas',
            ),
          ],
        ),
        body: finance.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Não foi possível ler os dados.')),
          data: (data) => switch (_tab) {
            0 => _Overview(
                data: data,
                discreet: session.discreet,
                mainCurrency: profile?.mainCurrency ?? Currency.aoa,
                onToggleDiscreet: controller.toggleDiscreet,
                onSeeAll: () => setState(() => _tab = 1),
              ),
            1 => MovementsView(data: data, discreet: session.discreet),
            _ => _AccountsView(data: data, discreet: session.discreet),
          },
        ),
      ),
    );
  }
}

/// Cartão translúcido sobre o fundo fotográfico.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(FtRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(FtSpace.lg),
      child: child,
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.data,
    required this.discreet,
    required this.mainCurrency,
    required this.onToggleDiscreet,
    required this.onSeeAll,
  });

  final FinanceData data;
  final bool discreet;
  final Currency mainCurrency;
  final VoidCallback onToggleDiscreet;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final ledger = data.ledger;
    final available = ledger.balances(availableOnly: true);
    final total = ledger.balances();
    final now = DateTime.now();
    final month = ledger.totals(DateTime(now.year, now.month), now);
    final recent = ledger.active().take(5).toList();
    final currencies = {...month.income.keys, ...month.expense.keys};
    if (currencies.isEmpty) currencies.add(mainCurrency);

    return ListView(
      padding: const EdgeInsets.fromLTRB(FtSpace.lg, FtSpace.sm, FtSpace.lg, 96),
      children: [
        _GlassCard(
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
                      _Amount(Money.zero(mainCurrency), discreet: discreet, large: true),
                    for (final m in available.values)
                      _Amount(m, discreet: discreet, large: true),
                  ],
                ),
              ),
              if (total.length != available.length ||
                  total.entries.any((e) => available[e.key] != e.value)) ...[
                const SizedBox(height: FtSpace.sm),
                Text('Total em todas as contas', style: theme.textTheme.labelMedium),
                for (final m in total.values) _Amount(m, discreet: discreet),
              ],
            ],
          ),
        ),
        const SizedBox(height: FtSpace.md),
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Este mês · ${monthName(now.month)}',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: FtSpace.sm),
              for (final c in currencies)
                Row(
                  children: [
                    Expanded(
                      child: _Flow(
                        label: 'Entradas',
                        icon: Icons.south_west,
                        color: colors.income,
                        text: amountText(month.income[c] ?? Money.zero(c), discreet: discreet),
                      ),
                    ),
                    Expanded(
                      child: _Flow(
                        label: 'Saídas',
                        icon: Icons.north_east,
                        color: colors.expense,
                        text: amountText(month.expense[c] ?? Money.zero(c), discreet: discreet),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: FtSpace.lg),
        Text('Contas', style: theme.textTheme.titleMedium),
        const SizedBox(height: FtSpace.xs),
        for (final a in data.openAccounts) _AccountRow(account: a, data: data, discreet: discreet),
        const SizedBox(height: FtSpace.lg),
        Row(
          children: [
            Expanded(child: Text('Movimentos recentes', style: theme.textTheme.titleMedium)),
            if (recent.isNotEmpty) TextButton(onPressed: onSeeAll, child: const Text('Ver todos')),
          ],
        ),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FtSpace.md),
            child: Text(
              'Registe a primeira despesa ou entrada no botão "Movimento".',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final m in recent) MovementTile(movement: m, data: data, discreet: discreet),
      ],
    );
  }
}

class _Flow extends StatelessWidget {
  const _Flow({required this.label, required this.icon, required this.color, required this.text});

  final String label;
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: FtSpace.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  text,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: ftAmountFeatures,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.data, required this.discreet});

  final Account account;
  final FinanceData data;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = account;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: FtSpace.xs),
      leading: CircleAvatar(child: Icon(accountTypeIcon(a.type))),
      title: Text(a.name),
      subtitle: Text([
        accountTypeLabel(a.type),
        if (a.institution != null) a.institution!,
        if (!a.includeInAvailable) 'fora do disponível',
      ].join(' · ')),
      trailing: Text(
        amountText(data.ledger.balanceOf(a.id), discreet: discreet),
        semanticsLabel: discreet ? 'Valor oculto' : null,
        style: theme.textTheme.titleSmall?.copyWith(fontFeatures: ftAmountFeatures),
      ),
    );
  }
}

class _AccountsView extends StatelessWidget {
  const _AccountsView({required this.data, required this.discreet});

  final FinanceData data;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(FtSpace.lg, FtSpace.sm, FtSpace.lg, 96),
      children: [
        for (final a in data.openAccounts) _AccountRow(account: a, data: data, discreet: discreet),
        const SizedBox(height: FtSpace.md),
        Text(
          'O saldo de cada conta é o saldo inicial mais os movimentos registados. '
          'A instituição serve só para organizar: o FINTRACK não se liga ao banco.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        amountText(money, discreet: discreet),
        semanticsLabel: discreet ? 'Valor oculto' : null,
        style: style?.copyWith(fontFeatures: ftAmountFeatures, fontWeight: FontWeight.w600),
      ),
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

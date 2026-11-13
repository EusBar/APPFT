import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_view.dart';
import '../cloud/cloud_controller.dart';
import '../design/backdrop.dart';
import '../design/country_photos.dart';
import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../finance/movement_form_screen.dart';
import '../finance/movement_tile.dart';
import '../finance/movements_screen.dart';
import '../planning/commitment_form_screen.dart';
import '../profile/profile_screen.dart';
import '../reports/report_screen.dart';
import '../notifications/reminders.dart';
import '../planning/budgets_view.dart';
import '../planning/goals_view.dart';
import '../planning/kixikila_view.dart';
import '../planning/planning_view.dart';
import '../privacy/consent.dart';
import '../security/session.dart';
import '../settings/settings_screen.dart';
import 'account_form.dart';
import 'account_sheet.dart';
import 'month_flow_card.dart';
import 'tips.dart';

/// Ecrã principal: Início, Movimentos, Planear, Contas.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Depois de desbloquear: lê a sessão da nuvem e sincroniza.
    Future.microtask(() async {
      final cloud = ref.read(cloudProvider.notifier);
      await cloud.load();
      if (mounted && ref.read(cloudProvider).signedIn) await cloud.syncNow();
    });
  }
  PlanSection _plan = PlanSection.commitments;

  Widget? _fab(FinanceData? data, Currency? mainCurrency) {
    if (data == null) return null;
    final (String, Widget Function())? action = switch (_tab) {
      3 => null,
      2 => switch (_plan) {
          PlanSection.commitments => ('Compromisso', () => CommitmentFormScreen(data: data)),
          PlanSection.budgets => ('Orçamento', () => BudgetFormScreen(data: data)),
          PlanSection.goals => ('Objetivo', () => GoalFormScreen(data: data)),
          PlanSection.kixikila => ('Kixikila', () => KixikilaFormScreen(data: data)),
        },
      4 => ('Nova conta', () => NewAccountScreen(defaultCurrency: mainCurrency ?? Currency.aoa)),
      _ => ('Movimento', () => MovementFormScreen(data: data)),
    };
    if (action == null) return null;
    final (label, open) = action;
    return FloatingActionButton.extended(
      heroTag: 'fab',
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => open())),
      icon: const Icon(Icons.add),
      label: Text(label),
    );
  }

  /// Só alterações depois da primeira leitura contam como "mudou algo".
  static bool previousHadData(AsyncValue<FinanceData>? previous) => previous?.valueOrNull != null;

  /// Reagenda os lembretes sempre que os dados mudam, se autorizados.
  Future<void> _syncReminders(FinanceData data) async {
    final allowed = await ref.read(secretStoreProvider).read(Consent.notifications.key) == '1';
    if (allowed) await ref.read(remindersProvider).reschedule(data);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(financeProvider, (prev, next) {
      final data = next.valueOrNull;
      if (data != null) {
        _syncReminders(data);
        if (previousHadData(prev)) ref.read(cloudProvider.notifier).scheduleSync();
      }
    });
    final session = ref.watch(sessionProvider);
    final controller = ref.read(sessionProvider.notifier);
    final finance = ref.watch(financeProvider);
    final profile = session.profile;
    final mainCurrency = profile?.mainCurrency ?? Currency.aoa;

    final title = switch (_tab) {
      0 => profile == null ? 'FINTRACK' : 'Olá, ${profile.greetingName}',
      1 => 'Movimentos',
      2 => 'Planear',
      3 => 'FINTRACK AI',
      _ => 'Contas',
    };

    return RotatingBackdrop(
      assets: [for (final p in photosFor(mainCurrency)) p.asset],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          titleSpacing: _tab == 0 ? 0 : null,
          leading: _tab != 0
              ? null
              : IconButton(
                  tooltip: 'Perfil',
                  icon: ProfileAvatar(profile: profile, radius: 16),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
                  ),
                ),
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
        floatingActionButton: _fab(finance.valueOrNull, profile?.mainCurrency),
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
              icon: Icon(Icons.event_note_outlined),
              selectedIcon: Icon(Icons.event_note),
              label: 'Planear',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'IA',
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
                horizon: session.horizon,
                mainCurrency: mainCurrency,
                onToggleDiscreet: controller.toggleDiscreet,
                onSeeMovements: () => setState(() => _tab = 1),
                onOpenPlanning: (s) => setState(() {
                  _tab = 2;
                  _plan = s;
                }),
              ),
            1 => MovementsView(data: data, discreet: session.discreet),
            2 => PlanningView(
                data: data,
                discreet: session.discreet,
                section: _plan,
                onSection: (s) => setState(() => _plan = s),
              ),
            3 => AiView(data: data, discreet: session.discreet),
            _ => _AccountsView(data: data, discreet: session.discreet),
          },
        ),
      ),
    );
  }
}

/// Cartão translúcido sobre o fundo fotográfico.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(FtSpace.lg)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(FtRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      padding: padding,
      child: child,
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({
    required this.data,
    required this.discreet,
    required this.horizon,
    required this.mainCurrency,
    required this.onToggleDiscreet,
    required this.onSeeMovements,
    required this.onOpenPlanning,
  });

  final FinanceData data;
  final bool discreet;
  final AvailableHorizon horizon;
  final Currency mainCurrency;
  final VoidCallback onToggleDiscreet;
  final VoidCallback onSeeMovements;
  final ValueChanged<PlanSection> onOpenPlanning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ledger = data.ledger;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recent = ledger.active().take(5).toList();

    Widget sectionHeader(String text, {VoidCallback? onMore}) => Row(
          children: [
            Expanded(child: Text(text, style: theme.textTheme.titleMedium)),
            if (onMore != null) TextButton(onPressed: onMore, child: const Text('Ver todos')),
          ],
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(FtSpace.lg, FtSpace.sm, FtSpace.lg, 96),
      children: [
        _AvailableCard(
          ledger: ledger,
          today: today,
          horizon: horizon,
          mainCurrency: mainCurrency,
          discreet: discreet,
          onToggleDiscreet: onToggleDiscreet,
        ),
        const SizedBox(height: FtSpace.sm),
        const TipsTicker(),
        const SizedBox(height: FtSpace.sm),
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => ReportScreen(initialMonth: today)),
          ),
          child: MonthFlowCard(ledger: ledger, today: today, mainCurrency: mainCurrency, discreet: discreet),
        ),
        const SizedBox(height: FtSpace.md),
        PlanningSummaryCard(data: data, onOpen: onOpenPlanning),
        const SizedBox(height: FtSpace.lg),
        sectionHeader('Contas'),
        for (final a in data.openAccounts) _AccountRow(account: a, data: data, discreet: discreet),
        const SizedBox(height: FtSpace.lg),
        sectionHeader('Movimentos recentes', onMore: recent.isEmpty ? null : onSeeMovements),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FtSpace.md),
            child: Text(
              'Registe a primeira despesa ou entrada no botão "Movimento".',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        for (final m in recent) MovementTile(movement: m, data: data, discreet: discreet),
      ],
    );
  }
}

class _AvailableCard extends ConsumerWidget {
  const _AvailableCard({
    required this.ledger,
    required this.today,
    required this.horizon,
    required this.mainCurrency,
    required this.discreet,
    required this.onToggleDiscreet,
  });

  final Ledger ledger;
  final DateTime today;
  final AvailableHorizon horizon;
  final Currency mainCurrency;
  final bool discreet;
  final VoidCallback onToggleDiscreet;

  Future<void> _chooseHorizon(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<AvailableHorizon>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Horizonte do saldo disponível'),
              subtitle: Text('Compromissos pendentes até esta data reduzem o disponível.'),
            ),
            for (final h in AvailableHorizon.values)
              ListTile(
                leading: Icon(h == horizon ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text(horizonLabel(h)),
                trailing: Text('até ${shortDate(h.end(today))}'),
                onTap: () => Navigator.of(context).pop(h),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await ref.read(sessionProvider.notifier).setHorizon(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final available = ledger.available(today: today, horizon: horizon);
    final committed = ledger.committed(today: today, horizon: horizon);
    final booked = ledger.balances(availableOnly: true);
    final total = ledger.balances();
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    String money(Money m) => amountText(m, discreet: discreet);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Saldo disponível', style: theme.textTheme.labelLarge)),
              InkWell(
                borderRadius: BorderRadius.circular(FtRadius.lg),
                onTap: () => _chooseHorizon(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: FtSpace.sm, vertical: FtSpace.xs),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(FtRadius.lg),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('até ${shortDate(horizon.end(today))}', style: theme.textTheme.labelMedium),
                      const Icon(Icons.expand_more, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FtSpace.xs),
          GestureDetector(
            onDoubleTap: onToggleDiscreet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (available.isEmpty) _Amount(Money.zero(mainCurrency), discreet: discreet, large: true),
                for (final m in available.values) _Amount(m, discreet: discreet, large: true),
              ],
            ),
          ),
          if (committed.isNotEmpty) ...[
            const SizedBox(height: FtSpace.sm),
            for (final cur in committed.keys) ...[
              _DetailRow(label: 'Saldo contabilístico', value: money(booked[cur] ?? Money.zero(cur)), style: muted),
              _DetailRow(
                label: 'Compromissos pendentes',
                value: discreet ? '••••••' : '−${committed[cur]!.format()}',
                style: muted?.copyWith(color: colors.commitment),
              ),
            ],
          ],
          if (total.length != booked.length || total.entries.any((e) => booked[e.key] != e.value)) ...[
            const SizedBox(height: FtSpace.xs),
            for (final m in total.values)
              _DetailRow(label: 'Total em todas as contas', value: money(m), style: muted),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.style});

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style?.copyWith(fontFeatures: ftAmountFeatures)),
        ],
      ),
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
      onTap: () => showAccountSheet(context, a, data),
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
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.fromLTRB(FtSpace.lg, FtSpace.sm, FtSpace.lg, 96),
      children: [
        for (final a in data.openAccounts) _AccountRow(account: a, data: data, discreet: discreet),
        if (data.archivedAccounts.isNotEmpty)
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: FtSpace.xs),
            title: Text('Arquivadas (${data.archivedAccounts.length})', style: theme.textTheme.titleSmall),
            children: [
              for (final a in data.archivedAccounts) _AccountRow(account: a, data: data, discreet: discreet),
            ],
          ),
        const SizedBox(height: FtSpace.lg),
        GlassCard(
          padding: const EdgeInsets.all(FtSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: muted),
              const SizedBox(width: FtSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'METODOLOGIA',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: FtSpace.xs),
                    Text(
                      'Saldo contabilístico = saldo de abertura + movimentos lançados no '
                      'livro-razão, estornos incluídos. Recalculado a partir dos registos '
                      'originais, nunca editado diretamente.',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.4),
                    ),
                    const SizedBox(height: FtSpace.xs),
                    Text(
                      'A instituição é um atributo de organização. O FINTRACK não estabelece '
                      'ligação a sistemas bancários nem acede a credenciais.',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
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

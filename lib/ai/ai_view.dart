import 'dart:convert';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../finance/movement_form_screen.dart';
import '../finance/movement_tile.dart';
import '../security/session.dart';
import 'copilot_card.dart';

/// Separador FINTRACK AI. Nesta versão tudo corre no telemóvel, sem
/// Internet: Smart Entry por texto ou SMS colado e o AI Guard.
class AiView extends ConsumerStatefulWidget {
  const AiView({super.key, required this.data, required this.discreet});

  final FinanceData data;
  final bool discreet;

  @override
  ConsumerState<AiView> createState() => _AiViewState();
}

class _AiViewState extends ConsumerState<AiView> {
  static const _kDismissed = 'ai.dismissed';
  final _text = TextEditingController();
  EntryDraft? _draft;
  Set<String> _dismissed = {};

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadDismissed() async {
    final raw = await ref.read(sessionProvider.notifier).store?.getSetting(_kDismissed);
    if (!mounted || raw == null) return;
    setState(() => _dismissed = {for (final x in jsonDecode(raw) as List<Object?>) x! as String});
  }

  Future<void> _dismiss(String id) async {
    final next = {..._dismissed, id};
    setState(() => _dismissed = next);
    await ref.read(sessionProvider.notifier).store?.setSetting(_kDismissed, jsonEncode(next.toList()));
  }

  void _prepare() {
    final data = widget.data;
    setState(() {
      _draft = _text.text.trim().isEmpty
          ? null
          : SmartEntryParser.parse(
              _text.text,
              accounts: data.accounts,
              categories: data.categories,
              today: DateTime.now(),
              suggester: data.suggester,
            );
    });
  }

  Future<void> _review() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => MovementFormScreen(data: widget.data, draft: _draft),
    ));
    if (saved == true && mounted) {
      setState(() {
        _draft = null;
        _text.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final alerts = AiGuard.scan(widget.data.ledger, today: DateTime.now(), dismissed: _dismissed);

    return ListView(
      padding: const EdgeInsets.fromLTRB(FtSpace.lg, FtSpace.sm, FtSpace.lg, 96),
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: colors.aiAccent),
            const SizedBox(width: FtSpace.sm),
            Expanded(
              child: Text(
                'Nada é gravado sem a sua confirmação · Smart Entry e AI Guard funcionam sem Internet',
                style: muted?.copyWith(color: colors.aiAccent),
              ),
            ),
          ],
        ),
        const SizedBox(height: FtSpace.md),
        CopilotCard(data: widget.data),
        const SizedBox(height: FtSpace.lg),
        _Card(
          accent: colors.aiAccent,
          children: [
            Text('Smart Entry', style: theme.textTheme.titleMedium),
            const SizedBox(height: FtSpace.xs),
            Text('Escreva como diria, ou cole o SMS do banco.', style: muted),
            const SizedBox(height: FtSpace.sm),
            TextField(
              key: const Key('smart-entry'),
              controller: _text,
              minLines: 2,
              maxLines: 5,
              maxLength: 400,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Ex.: Gastei 12 500 Kz no Kero hoje',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _prepare(),
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Preparar movimento'),
              onPressed: _prepare,
            ),
            if (_draft != null) ...[
              const SizedBox(height: FtSpace.md),
              _DraftPreview(draft: _draft!, data: widget.data),
              const SizedBox(height: FtSpace.sm),
              FilledButton(
                onPressed: _draft!.kind == MovementKind.transfer ? null : _review,
                child: Text(_draft!.complete ? 'Rever e gravar' : 'Completar e gravar'),
              ),
            ],
          ],
        ),
        const SizedBox(height: FtSpace.lg),
        Row(
          children: [
            Icon(Icons.shield_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: FtSpace.sm),
            Text('AI Guard', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: FtSpace.xs),
        Text(
          'Sinais para verificar nos últimos 45 dias. Um alerta não é uma acusação: '
          'confirme, corrija ou marque como legítimo.',
          style: muted,
        ),
        const SizedBox(height: FtSpace.sm),
        if (alerts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FtSpace.md),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: colors.income),
                const SizedBox(width: FtSpace.sm),
                const Expanded(child: Text('Nada a assinalar.')),
              ],
            ),
          ),
        for (final a in alerts)
          _AlertTile(
            alert: a,
            data: widget.data,
            discreet: widget.discreet,
            onDismiss: () => _dismiss(a.id),
          ),
        const SizedBox(height: FtSpace.xl),
        Text(
          'O FINTRACK AI é apoio à decisão, não aconselhamento financeiro profissional.',
          style: muted,
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children, required this.accent});

  final List<Widget> children;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(FtSpace.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(FtRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _DraftPreview extends StatelessWidget {
  const _DraftPreview({required this.draft, required this.data});

  final EntryDraft draft;
  final FinanceData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final d = draft;
    final missingStyle = TextStyle(color: colors.alert, fontWeight: FontWeight.w600);
    Widget row(String label, String? value, {bool missing = false, String? hint}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 90, child: Text(label, style: theme.textTheme.bodySmall)),
              Expanded(
                child: Text(
                  missing ? 'Por indicar' : '${value ?? ''}${hint == null ? '' : ' · $hint'}',
                  style: missing ? missingStyle : const TextStyle(fontFeatures: ftAmountFeatures),
                ),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('Tipo', d.kind == null ? null : movementKindLabel(d.kind!), missing: d.missing.contains(EntryField.kind)),
        row('Valor', d.amount?.format(), missing: d.missing.contains(EntryField.amount)),
        row('Conta', data.account(d.accountId)?.name, missing: d.missing.contains(EntryField.account)),
        if (d.kind != MovementKind.transfer)
          row('Categoria', data.category(d.categoryId)?.name, missing: d.missing.contains(EntryField.category)),
        row('Data', dayLabel(d.date), hint: d.dateAssumed ? 'assumida' : null),
        if (d.description.isNotEmpty) row('Descrição', d.description),
        for (final n in d.notes)
          Padding(
            padding: const EdgeInsets.only(top: FtSpace.xs),
            child: Text(n, style: theme.textTheme.bodySmall?.copyWith(color: colors.alert)),
          ),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, required this.data, required this.discreet, required this.onDismiss});

  final GuardAlert alert;
  final FinanceData data;
  final bool discreet;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    String money(Money? m) => m == null ? '' : amountText(m, discreet: discreet);
    final movement = alert.movementId == null ? null : data.ledger.byId(alert.movementId!);
    final color = alert.priority >= 3 ? colors.expense : colors.alert;
    final (icon, title, body) = switch (alert.kind) {
      GuardKind.duplicate => (
          Icons.copy_all_outlined,
          'Possível duplicado',
          'Dois movimentos de ${money(alert.amount)} na mesma conta e no mesmo dia'
              '${movement == null ? '' : ' (${dayLabel(movement.date)})'}.',
        ),
      GuardKind.unusualAmount => (
          Icons.trending_up,
          'Valor fora do habitual',
          '${money(alert.amount)} em ${data.category(alert.categoryId)?.name ?? '?'}; '
              'o habitual nesta categoria é cerca de ${money(alert.typical)}.',
        ),
      GuardKind.availableNegative => (
          Icons.warning_amber_rounded,
          'Saldo disponível negativo',
          'Com os compromissos até ao fim do mês, o disponível fica em ${money(alert.amount)}.',
        ),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: FtSpace.sm),
      padding: const EdgeInsets.all(FtSpace.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(FtRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: FtSpace.sm),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: color))),
            ],
          ),
          const SizedBox(height: FtSpace.xs),
          Text(body, style: theme.textTheme.bodyMedium),
          Wrap(
            spacing: FtSpace.sm,
            children: [
              if (movement != null)
                TextButton(
                  onPressed: () => showMovementDetails(context, movement, data),
                  child: const Text('Ver movimento'),
                ),
              if (alert.kind != GuardKind.availableNegative)
                TextButton(onPressed: onDismiss, child: const Text('É legítimo')),
            ],
          ),
        ],
      ),
    );
  }
}

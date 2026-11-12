import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../security/session.dart';

/// Kixikila: grupos, próxima contribuição e a sua vez de receber.
class KixikilaView extends StatelessWidget {
  const KixikilaView({super.key, required this.data, required this.discreet});

  final FinanceData data;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = [for (final g in data.kixikilas) if (!g.archived) g];
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(FtSpace.xl),
        child: Text(
          'Acompanhe a sua Kixikila: quanto contribui, quando é a próxima ronda e quando é a '
          'sua vez de receber. Os outros membros são só nomes; nenhum dado é partilhado.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      children: [
        for (final g in groups)
          _KixikilaCard(
            data: data,
            status: KixikilaEngine.status(data.ledger, g, data.kixikilaRecords),
            discreet: discreet,
          ),
      ],
    );
  }
}

class _KixikilaCard extends ConsumerWidget {
  const _KixikilaCard({required this.data, required this.status, required this.discreet});

  final FinanceData data;
  final KixikilaStatus status;
  final bool discreet;

  Future<void> _record(BuildContext context, WidgetRef ref, KixikilaRecordKind kind) async {
    final g = status.group;
    final round = kind == KixikilaRecordKind.payout ? g.myTurn : status.nextContribution;
    if (round == null) return;
    final payout = kind == KixikilaRecordKind.payout;
    final amount = payout ? g.payout : g.contribution;
    final account = data.account(g.accountId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(payout ? 'Registar recebimento' : 'Registar contribuição'),
        content: Text(
          payout
              ? 'Entrada de ${amount.format()} na conta ${account?.name ?? '?'}, categoria Kixikila.'
              : 'Saída de ${amount.format()} da conta ${account?.name ?? '?'} (ronda ${round + 1} de ${g.rounds}), '
                  'categoria Kixikila.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Registar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final store = ref.read(sessionProvider.notifier).store;
    if (store == null) return;
    final now = DateTime.now();
    final movement = Movement(
      id: newId(),
      kind: payout ? MovementKind.income : MovementKind.expense,
      accountId: g.accountId,
      amount: amount,
      categoryId: payout ? 'inc.kixikila' : 'exp.kixikila',
      description: 'Kixikila ${g.name} · ronda ${round + 1}',
      date: now,
      createdAt: now,
    );
    final messenger = ScaffoldMessenger.of(context);
    final issue = data.ledger.check(movement, today: now);
    if (issue != null) {
      messenger.showSnackBar(SnackBar(content: Text(movementIssueMessage(issue))));
      return;
    }
    await store.recordKixikila(
      movement,
      KixikilaRecord(
        id: newId(),
        groupId: g.id,
        round: round,
        kind: kind,
        movementId: movement.id,
        createdAt: now,
      ),
    );
    ref.invalidate(financeProvider);
    messenger.showSnackBar(SnackBar(content: Text(payout ? 'Recebimento registado.' : 'Contribuição registada.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final g = status.group;
    final next = status.nextContribution;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    String money(Money m) => amountText(m, discreet: discreet);

    return Padding(
      padding: const EdgeInsets.only(bottom: FtSpace.md),
      child: Container(
        padding: const EdgeInsets.all(FtSpace.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(FtRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.groups_outlined, color: colors.commitment),
                const SizedBox(width: FtSpace.sm),
                Expanded(child: Text(g.name, style: theme.textTheme.titleMedium)),
                Text('${status.paidRounds.length}/${g.rounds}', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: FtSpace.sm),
            // Rondas: cheias as pagas; anel na sua vez.
            Row(
              children: [
                for (var k = 0; k < g.rounds; k++)
                  Expanded(
                    child: Container(
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: status.paidRounds.contains(k)
                            ? (k == g.myTurn ? colors.income : theme.colorScheme.primary)
                            : theme.colorScheme.onSurface.withValues(alpha: k == g.myTurn ? 0.3 : 0.1),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: FtSpace.sm),
            Text(
              '${money(g.contribution)} por ${g.period == Recurrence.weekly ? 'semana' : 'mês'} · '
              '${g.rounds} membros',
              style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: ftAmountFeatures),
            ),
            Text(
              next == null
                  ? 'Todas as contribuições registadas.'
                  : 'Próxima contribuição: ${dayLabel(g.roundDate(next))} (ronda ${next + 1}, recebe ${g.members[next]})',
              style: muted,
            ),
            Text(
              status.received
                  ? 'Já recebeu ${money(g.payout)}.'
                  : 'A sua vez: ${dayLabel(status.myPayoutDate)} · recebe ${money(g.payout)}',
              style: muted?.copyWith(color: status.received ? colors.income : null),
            ),
            const SizedBox(height: FtSpace.sm),
            Wrap(
              spacing: FtSpace.sm,
              children: [
                if (next != null)
                  FilledButton.tonal(
                    onPressed: () => _record(context, ref, KixikilaRecordKind.contribution),
                    child: const Text('Registar contribuição'),
                  ),
                if (!status.received)
                  OutlinedButton(
                    onPressed: () => _record(context, ref, KixikilaRecordKind.payout),
                    child: const Text('Registar recebimento'),
                  ),
                if (status.finished)
                  TextButton(
                    onPressed: () async {
                      final store = ref.read(sessionProvider.notifier).store;
                      if (store == null) return;
                      await store.saveKixikilaGroup(g.copyWith(archived: true));
                      ref.invalidate(financeProvider);
                    },
                    child: const Text('Arquivar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Criar uma Kixikila.
class KixikilaFormScreen extends ConsumerStatefulWidget {
  const KixikilaFormScreen({super.key, required this.data});

  final FinanceData data;

  @override
  ConsumerState<KixikilaFormScreen> createState() => _KixikilaFormScreenState();
}

class _KixikilaFormScreenState extends ConsumerState<KixikilaFormScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _members = <TextEditingController>[TextEditingController(text: 'Eu'), TextEditingController()];
  int _myTurn = 0;
  Recurrence _period = Recurrence.monthly;
  DateTime _start = DateTime.now();
  late String? _accountId = widget.data.openAccounts.firstOrNull?.id;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    for (final c in _members) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final account = widget.data.account(_accountId);
    if (account == null) return;
    try {
      final contribution = Money.parse(_amount.text, account.currency);
      final now = DateTime.now();
      final group = KixikilaGroup(
        id: newId(),
        name: _name.text,
        members: [for (final c in _members) c.text],
        contribution: contribution,
        period: _period,
        startDate: _start,
        myTurn: _myTurn,
        accountId: account.id,
        createdAt: now,
      );
      final store = ref.read(sessionProvider.notifier).store;
      if (store == null) return;
      await store.saveKixikilaGroup(group);
      ref.invalidate(financeProvider);
      if (mounted) Navigator.of(context).pop();
    } on FormatException {
      setState(() => _error = 'Indique o valor da contribuição. Exemplo: 50 000');
    } on ArgumentError {
      setState(() => _error = 'Preencha o nome do grupo, o nome de cada membro e um valor maior que zero.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = widget.data.account(_accountId);
    return Scaffold(
      appBar: AppBar(title: const Text('Nova Kixikila')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FtSpace.lg),
          children: [
            TextField(
              key: const Key('kixikila-name'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome do grupo',
                hintText: 'Ex.: Kixikila do trabalho',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FtSpace.md),
            TextField(
              key: const Key('kixikila-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Contribuição por ronda',
                suffixText: account?.currency.symbol,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FtSpace.md),
            SegmentedButton<Recurrence>(
              segments: const [
                ButtonSegment(value: Recurrence.monthly, label: Text('Mensal')),
                ButtonSegment(value: Recurrence.weekly, label: Text('Semanal')),
              ],
              selected: {_period},
              onSelectionChanged: (v) => setState(() => _period = v.first),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Primeira ronda'),
              subtitle: Text(dayLabel(_start)),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _start,
                  firstDate: DateTime(now.year - 2),
                  lastDate: DateTime(now.year + 2),
                );
                if (picked != null) setState(() => _start = picked);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(labelText: 'Conta usada', border: OutlineInputBorder()),
              items: [
                for (final a in widget.data.openAccounts) DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: FtSpace.lg),
            Text('Membros, pela ordem de recebimento', style: theme.textTheme.titleSmall),
            Text('Toque no círculo para indicar a sua vez.', style: theme.textTheme.bodySmall),
            const SizedBox(height: FtSpace.sm),
            RadioGroup<int>(
              groupValue: _myTurn,
              onChanged: (v) => setState(() => _myTurn = v ?? _myTurn),
              child: Column(
                children: [
                  for (final (i, c) in _members.indexed)
                    Row(
                      children: [
                        Radio<int>(value: i),
                        Expanded(
                          child: TextField(
                            key: Key('kixikila-member-$i'),
                            controller: c,
                            decoration: InputDecoration(
                              labelText: 'Ronda ${i + 1}',
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remover membro',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _members.length <= 2
                              ? null
                              : () => setState(() {
                                    _members.removeAt(i).dispose();
                                    if (_myTurn >= _members.length) _myTurn = _members.length - 1;
                                  }),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Adicionar membro'),
              onPressed: () => setState(() => _members.add(TextEditingController())),
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: FtSpace.lg),
            FilledButton(onPressed: _save, child: const Text('Guardar Kixikila')),
          ],
        ),
      ),
    );
  }
}

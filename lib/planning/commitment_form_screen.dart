import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../security/session.dart';

/// Criar ou editar um compromisso (pagamento previsto).
class CommitmentFormScreen extends ConsumerStatefulWidget {
  const CommitmentFormScreen({super.key, required this.data, this.editing});

  final FinanceData data;
  final Commitment? editing;

  @override
  ConsumerState<CommitmentFormScreen> createState() => _CommitmentFormScreenState();
}

class _CommitmentFormScreenState extends ConsumerState<CommitmentFormScreen> {
  late String? _accountId;
  String? _categoryId;
  late DateTime _due;
  late Recurrence _recurrence = widget.editing?.recurrence ?? Recurrence.none;
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _note = TextEditingController();
  String? _amountError;
  String? _descriptionError;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    final accounts = widget.data.openAccounts;
    _accountId = e?.accountId ?? (accounts.isEmpty ? null : accounts.first.id);
    _categoryId = e?.categoryId;
    final now = DateTime.now();
    _due = e?.dueDate ?? DateTime(now.year, now.month, now.day + 7);
    if (e != null) {
      _amount.text = e.amount.format(withSymbol: false);
      _description.text = e.description;
      _note.text = e.note;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Data prevista',
      cancelText: 'Cancelar',
      confirmText: 'OK',
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    final account = widget.data.account(_accountId);
    if (account == null) {
      setState(() => _error = 'Escolha a conta.');
      return;
    }
    Money? amount;
    String? amountError;
    try {
      amount = Money.parse(_amount.text, account.currency);
      if (amount.minor <= 0) amountError = 'O valor tem de ser maior que zero.';
    } on FormatException {
      amountError = _amount.text.trim().isEmpty ? 'Indique o valor.' : 'Valor inválido. Exemplo: 45 000,00';
    }
    final descriptionError = _description.text.trim().isEmpty ? 'Descreva o compromisso.' : null;
    setState(() {
      _amountError = amountError;
      _descriptionError = descriptionError;
      _error = _categoryId == null ? 'Escolha uma categoria.' : null;
    });
    if (amountError != null || descriptionError != null || _categoryId == null) return;

    final base = widget.editing?.asPending();
    final commitment = Commitment(
      id: base?.id ?? newId(),
      accountId: account.id,
      amount: amount!,
      categoryId: _categoryId!,
      description: _description.text,
      note: _note.text,
      dueDate: _due,
      recurrence: _recurrence,
      seriesId: base?.seriesId,
      anchorDay: base == null || base.dueDate != DateTime(_due.year, _due.month, _due.day) ? null : base.anchorDay,
      createdAt: base?.createdAt ?? DateTime.now(),
    );

    final store = ref.read(sessionProvider.notifier).store;
    if (store == null) return;
    setState(() => _busy = true);
    try {
      final issue = await LedgerWriter(store, widget.data).saveCommitment(commitment);
      if (!mounted) return;
      if (issue != null) {
        setState(() => _error = movementIssueMessage(issue));
        return;
      }
      ref.invalidate(financeProvider);
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível gravar. Tente de novo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final accounts = widget.data.openAccounts;
    final account = widget.data.account(_accountId);
    final categories = [
      for (final c in widget.data.categories)
        if (!c.archived && c.kind == CategoryKind.expense) c,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? 'Novo compromisso' : 'Editar compromisso'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FtSpace.lg),
          children: [
            Text(
              'Um pagamento previsto reduz o saldo disponível até ser pago. '
              'Ao pagar, o FINTRACK regista a saída por si.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: FtSpace.lg),
            TextField(
              key: const Key('commitment-description'),
              controller: _description,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Descrição',
                hintText: 'Ex.: Renda de dezembro',
                errorText: _descriptionError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FtSpace.sm),
            TextField(
              key: const Key('commitment-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFeatures: ftAmountFeatures,
                color: colors.commitment,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: 'Valor',
                hintText: '0,00',
                suffixText: account?.currency.symbol,
                errorText: _amountError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FtSpace.md),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(
                labelText: 'Conta que vai pagar',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.id, child: Text('${a.name} · ${a.currency.code}')),
              ],
              onChanged: (id) => setState(() => _accountId = id),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Data prevista'),
              subtitle: Text(dayLabel(_due)),
              onTap: _pickDate,
            ),
            DropdownButtonFormField<Recurrence>(
              initialValue: _recurrence,
              decoration: const InputDecoration(
                labelText: 'Repetição',
                helperText: 'Ao pagar, o FINTRACK prepara o seguinte. Nunca paga sozinho.',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final r in Recurrence.values)
                  DropdownMenuItem(value: r, child: Text(recurrenceLabel(r))),
              ],
              onChanged: (r) => setState(() => _recurrence = r ?? Recurrence.none),
            ),
            const SizedBox(height: FtSpace.md),
            Text('Categoria', style: theme.textTheme.labelLarge),
            const SizedBox(height: FtSpace.sm),
            Wrap(
              spacing: FtSpace.sm,
              runSpacing: FtSpace.sm,
              children: [
                for (final c in categories)
                  ChoiceChip(
                    avatar: Icon(categoryIcon(c.icon), size: 18),
                    label: Text(c.name),
                    selected: _categoryId == c.id,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  ),
              ],
            ),
            const SizedBox(height: FtSpace.lg),
            TextField(
              controller: _note,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Observações (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: FtSpace.sm),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: FtSpace.lg),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Guardar compromisso'),
            ),
          ],
        ),
      ),
    );
  }
}

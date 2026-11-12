import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/labels.dart';
import '../design/tokens.dart';
import '../security/session.dart';
import 'finance_data.dart';

/// Registo manual de uma entrada, saída ou transferência própria.
/// Com [editing], grava uma correção: estorno do original + registo novo.
class MovementFormScreen extends ConsumerStatefulWidget {
  const MovementFormScreen({
    super.key,
    required this.data,
    this.initialKind = MovementKind.expense,
    this.editing,
  });

  final FinanceData data;
  final MovementKind initialKind;
  final Movement? editing;

  @override
  ConsumerState<MovementFormScreen> createState() => _MovementFormScreenState();
}

class _MovementFormScreenState extends ConsumerState<MovementFormScreen> {
  late MovementKind _kind;
  late String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  bool _categoryTouched = false;
  bool _suggested = false;
  late DateTime _date;
  final _amount = TextEditingController();
  final _toAmount = TextEditingController();
  final _description = TextEditingController();
  final _note = TextEditingController();
  String? _amountError;
  String? _toAmountError;
  String? _error;
  bool _busy = false;

  FinanceData get _data => widget.data;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    final accounts = _data.openAccounts;
    _kind = e?.kind ?? widget.initialKind;
    _accountId = e?.accountId ?? (accounts.isEmpty ? null : accounts.first.id);
    _toAccountId = e?.toAccountId ?? _firstOther(_accountId);
    _categoryId = e?.categoryId;
    _date = e?.date ?? DateTime.now();
    if (e != null) {
      _amount.text = e.amount.format(withSymbol: false);
      _toAmount.text = e.toAmount?.format(withSymbol: false) ?? '';
      _description.text = e.description;
      _note.text = e.note;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _toAmount.dispose();
    _description.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _firstOther(String? id) {
    for (final a in _data.openAccounts) {
      if (a.id != id) return a.id;
    }
    return null;
  }

  /// IA local: sugere a categoria pelo histórico enquanto o utilizador não
  /// escolher uma à mão.
  void _suggestCategory(String description) {
    if (_categoryTouched || _kind == MovementKind.transfer) return;
    final suggestion = _data.suggester.suggest(description, _kind, _data.categories);
    if (suggestion != _categoryId) {
      setState(() {
        _categoryId = suggestion;
        _suggested = suggestion != null;
      });
    }
  }

  Account? get _from => _data.account(_accountId);
  Account? get _to => _data.account(_toAccountId);

  bool get _crossCurrency =>
      _kind == MovementKind.transfer &&
      _from != null &&
      _to != null &&
      _from!.currency != _to!.currency;

  Money? _parse(TextEditingController c, Currency currency, void Function(String?) setError) {
    final raw = c.text.trim();
    if (raw.isEmpty) {
      setError('Indique o valor.');
      return null;
    }
    try {
      final m = Money.parse(raw, currency);
      if (m.minor <= 0) {
        setError('O valor tem de ser maior que zero.');
        return null;
      }
      setError(null);
      return m;
    } on FormatException {
      setError('Valor inválido. Exemplo: 12 500,00');
      return null;
    }
  }

  Future<void> _save() async {
    final from = _from;
    if (from == null) {
      setState(() => _error = 'Escolha a conta.');
      return;
    }
    String? amountError;
    String? toAmountError;
    final amount = _parse(_amount, from.currency, (e) => amountError = e);
    Money? toAmount;
    if (_kind == MovementKind.transfer) {
      final to = _to;
      if (to == null) {
        setState(() => _error = 'Escolha a conta de destino.');
        return;
      }
      toAmount = _crossCurrency
          ? _parse(_toAmount, to.currency, (e) => toAmountError = e)
          : amount;
    }
    final needsCategory = _kind != MovementKind.transfer;
    final category = needsCategory ? _data.category(_categoryId) : null;
    final categoryOk = !needsCategory ||
        (category != null &&
            category.kind ==
                (_kind == MovementKind.income ? CategoryKind.income : CategoryKind.expense));
    setState(() {
      _amountError = amountError;
      _toAmountError = toAmountError;
      _error = categoryOk ? null : 'Escolha uma categoria.';
    });
    if (amount == null || !categoryOk) return;
    if (_kind == MovementKind.transfer && toAmount == null) return;

    final Movement movement;
    try {
      movement = Movement(
        id: newId(),
        kind: _kind,
        accountId: from.id,
        amount: amount,
        toAccountId: _kind == MovementKind.transfer ? _toAccountId : null,
        toAmount: toAmount,
        categoryId: needsCategory ? _categoryId : null,
        description: _description.text,
        note: _note.text,
        date: _date,
        replaces: widget.editing?.id,
        createdAt: DateTime.now(),
      );
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}.');
      return;
    }

    final duplicate = _data.ledger.possibleDuplicate(movement);
    if (duplicate != null && !await _confirmDuplicate(duplicate)) return;

    final store = ref.read(sessionProvider.notifier).store;
    if (store == null) return;
    setState(() => _busy = true);
    try {
      final issue = await LedgerWriter(store, _data).save(movement);
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

  Future<bool> _confirmDuplicate(Movement other) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Possível duplicado'),
        content: Text(
          'Já existe ${movementKindLabel(other.kind).toLowerCase()} de '
          '${other.amount.format()} na mesma conta e no mesmo dia'
          '${other.description.isEmpty ? '' : ' ("${other.description}")'}. '
          'Gravar mesmo assim?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Gravar'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final from = _from;
    var first = from?.startDate ?? DateTime(now.year - 1);
    final to = _kind == MovementKind.transfer ? _to : null;
    if (to != null && to.startDate.isAfter(first)) first = to.startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(first) ? first : _date,
      firstDate: first,
      lastDate: now,
      helpText: 'Data do movimento',
      cancelText: 'Cancelar',
      confirmText: 'OK',
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final accounts = _data.openAccounts;
    final accent = switch (_kind) {
      MovementKind.income => colors.income,
      MovementKind.expense => colors.expense,
      MovementKind.transfer => colors.transfer,
    };
    final categoryKind = _kind == MovementKind.income ? CategoryKind.income : CategoryKind.expense;
    final categories = [
      for (final c in _data.categories)
        if (!c.archived && c.kind == categoryKind) c,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? 'Novo movimento' : 'Corrigir movimento'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FtSpace.lg),
          children: [
            SegmentedButton<MovementKind>(
              segments: [
                for (final k in [MovementKind.expense, MovementKind.income, MovementKind.transfer])
                  ButtonSegment(value: k, label: Text(movementKindLabel(k))),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _categoryId = null;
                _categoryTouched = false;
                _suggested = false;
                _error = null;
              }),
            ),
            if (_kind == MovementKind.transfer && accounts.length < 2) ...[
              const SizedBox(height: FtSpace.md),
              Text(
                'Para transferir entre contas próprias, crie primeiro uma segunda conta.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: FtSpace.lg),
            TextField(
              key: const Key('movement-amount'),
              controller: _amount,
              autofocus: widget.editing == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontFeatures: ftAmountFeatures,
                color: accent,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: _kind == MovementKind.transfer ? 'Valor enviado' : 'Valor',
                hintText: '0,00',
                suffixText: _from?.currency.symbol,
                errorText: _amountError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FtSpace.md),
            DropdownButtonFormField<String>(
              key: ValueKey('from-$_kind'),
              initialValue: _accountId,
              decoration: InputDecoration(
                labelText: switch (_kind) {
                  MovementKind.income => 'Conta que recebe',
                  MovementKind.expense => 'Conta que paga',
                  MovementKind.transfer => 'De',
                },
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.id, child: Text('${a.name} · ${a.currency.code}')),
              ],
              onChanged: (id) => setState(() {
                _accountId = id;
                if (_toAccountId == id) _toAccountId = _firstOther(id);
              }),
            ),
            if (_kind == MovementKind.transfer) ...[
              const SizedBox(height: FtSpace.md),
              DropdownButtonFormField<String>(
                key: ValueKey('to-$_accountId'),
                initialValue: _toAccountId,
                decoration: const InputDecoration(
                  labelText: 'Para',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final a in accounts)
                    if (a.id != _accountId)
                      DropdownMenuItem(value: a.id, child: Text('${a.name} · ${a.currency.code}')),
                ],
                onChanged: (id) => setState(() => _toAccountId = id),
              ),
              if (_crossCurrency) ...[
                const SizedBox(height: FtSpace.md),
                TextField(
                  controller: _toAmount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontFeatures: ftAmountFeatures),
                  decoration: InputDecoration(
                    labelText: 'Valor recebido',
                    hintText: '0,00',
                    suffixText: _to?.currency.symbol,
                    helperText: 'Moedas diferentes: registe quanto chegou à outra conta.',
                    errorText: _toAmountError,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: FtSpace.lg),
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
                      onSelected: (_) => setState(() {
                        _categoryId = c.id;
                        _categoryTouched = true;
                        _suggested = false;
                      }),
                    ),
                ],
              ),
              if (_suggested && _categoryId != null)
                Padding(
                  padding: const EdgeInsets.only(top: FtSpace.xs),
                  child: Text(
                    'Sugerida a partir do seu histórico (no aparelho). Toque noutra para mudar.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.aiAccent),
                  ),
                ),
            ],
            const SizedBox(height: FtSpace.lg),
            TextField(
              key: const Key('movement-description'),
              controller: _description,
              maxLength: Movement.descriptionMaxLength,
              onChanged: _suggestCategory,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descrição (opcional)',
                hintText: 'Ex.: Compras no mercado',
                border: OutlineInputBorder(),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Data'),
              subtitle: Text(dayLabel(_date)),
              onTap: _pickDate,
            ),
            TextField(
              controller: _note,
              maxLength: Movement.noteMaxLength,
              minLines: 1,
              maxLines: 4,
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
              child: Text(widget.editing == null ? 'Gravar' : 'Gravar correção'),
            ),
            if (widget.editing != null) ...[
              const SizedBox(height: FtSpace.sm),
              Text(
                'O movimento original não é apagado: fica anulado por um estorno '
                'e esta versão passa a valer.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

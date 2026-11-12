import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';

import '../design/labels.dart';
import '../design/tokens.dart';

/// Formulário de conta, usado no onboarding e em "Nova conta".
class AccountForm extends StatefulWidget {
  const AccountForm({
    super.key,
    required this.defaultCurrency,
    required this.submitLabel,
    required this.onSubmit,
    this.allowCurrencyChoice = true,
    this.initial,
    this.openingEditable = true,
  });

  /// Conta a editar; `null` para uma conta nova.
  final Account? initial;

  /// O saldo inicial só se corrige enquanto a conta não tiver movimentos.
  final bool openingEditable;

  final Currency defaultCurrency;
  final String submitLabel;
  final bool allowCurrencyChoice;
  final Future<void> Function(Account account) onSubmit;

  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  late AccountType _type = widget.initial?.type ?? AccountType.bank;
  late Currency _currency = widget.initial?.currency ?? widget.defaultCurrency;
  late final _name = TextEditingController(
    text: widget.initial?.name ?? accountTypeDefaultName(AccountType.bank),
  );
  late final _institution = TextEditingController(text: widget.initial?.institution ?? '');
  late final _balance = TextEditingController(
    text: widget.initial?.openingBalance.format(withSymbol: false) ?? '',
  );
  late bool _nameEdited = widget.initial != null;
  String? _nameError;
  String? _balanceError;
  bool _busy = false;

  bool get _hasInstitution =>
      _type == AccountType.bank ||
      _type == AccountType.card ||
      _type == AccountType.mobileWallet;

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _selectType(AccountType t) {
    setState(() {
      _type = t;
      if (!_nameEdited) _name.text = accountTypeDefaultName(t);
    });
  }

  Future<void> _submit() async {
    final name = NameRules.clean(_name.text);
    Money? balance;
    String? balanceError;
    final raw = _balance.text.trim();
    if (raw.isEmpty) {
      balance = Money.zero(_currency);
    } else {
      try {
        balance = Money.parse(raw, _currency);
      } on FormatException {
        balanceError = 'Valor inválido. Exemplo: 12 500,00';
      }
    }
    setState(() {
      _nameError = name == null ? 'Escreva um nome (até ${NameRules.maxLength} letras).' : null;
      _balanceError = balanceError;
    });
    if (name == null || balance == null) return;

    final institution = _hasInstitution ? _institution.text : null;
    if (institution != null &&
        institution.trim().length > Account.institutionMaxLength) {
      return;
    }

    setState(() => _busy = true);
    try {
      final initial = widget.initial;
      await widget.onSubmit(initial == null
          ? Account(
              id: newId(),
              type: _type,
              name: name,
              institution: institution,
              openingBalance: balance,
              startDate: DateTime.now(),
            )
          : initial.copyWith(
              type: _type,
              name: name,
              institution: institution,
              clearInstitution: institution == null || institution.trim().isEmpty,
              openingBalance: widget.openingEditable ? balance : initial.openingBalance,
            ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tipo', style: theme.textTheme.labelLarge),
        const SizedBox(height: FtSpace.sm),
        Wrap(
          spacing: FtSpace.sm,
          runSpacing: FtSpace.sm,
          children: [
            for (final t in AccountType.values)
              ChoiceChip(
                avatar: Icon(accountTypeIcon(t), size: 18),
                label: Text(accountTypeLabel(t)),
                selected: _type == t,
                onSelected: (_) => _selectType(t),
              ),
          ],
        ),
        const SizedBox(height: FtSpace.lg),
        TextField(
          key: const Key('account-name'),
          controller: _name,
          maxLength: NameRules.maxLength,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => _nameEdited = true,
          decoration: InputDecoration(
            labelText: 'Nome da conta',
            errorText: _nameError,
            border: const OutlineInputBorder(),
          ),
        ),
        if (_hasInstitution) ...[
          const SizedBox(height: FtSpace.sm),
          TextField(
            controller: _institution,
            maxLength: Account.institutionMaxLength,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Instituição (opcional)',
              hintText: 'Ex.: BAI, BFA, Unitel Money',
              helperText: 'Só para organizar. Sem ligação ao banco.',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (widget.allowCurrencyChoice && widget.initial == null) ...[
          const SizedBox(height: FtSpace.sm),
          DropdownButtonFormField<Currency>(
            initialValue: _currency,
            decoration: const InputDecoration(
              labelText: 'Moeda',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final c in Currency.supported)
                DropdownMenuItem(value: c, child: Text('${c.code} · ${currencyName(c)}')),
            ],
            onChanged: (c) => setState(() => _currency = c ?? _currency),
          ),
        ],
        const SizedBox(height: FtSpace.md),
        TextField(
          key: const Key('account-balance'),
          controller: _balance,
          enabled: widget.openingEditable,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          style: const TextStyle(fontFeatures: ftAmountFeatures),
          decoration: InputDecoration(
            labelText: 'Saldo atual',
            hintText: '0,00',
            suffixText: _currency.symbol,
            helperText: widget.openingEditable
                ? 'Quanto tem hoje nesta conta. Pode deixar a zero.'
                : 'Já há movimentos: o saldo inicial fica fixo para não alterar o histórico.',
            helperMaxLines: 2,
            errorText: _balanceError,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: FtSpace.lg),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}

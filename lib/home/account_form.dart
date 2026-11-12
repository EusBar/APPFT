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
  });

  final Currency defaultCurrency;
  final String submitLabel;
  final bool allowCurrencyChoice;
  final Future<void> Function(Account account) onSubmit;

  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  AccountType _type = AccountType.bank;
  late Currency _currency = widget.defaultCurrency;
  final _name = TextEditingController(text: accountTypeDefaultName(AccountType.bank));
  final _institution = TextEditingController();
  final _balance = TextEditingController();
  bool _nameEdited = false;
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
      await widget.onSubmit(Account(
        id: newId(),
        type: _type,
        name: name,
        institution: institution,
        openingBalance: balance,
        startDate: DateTime.now(),
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
        if (widget.allowCurrencyChoice) ...[
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
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          style: const TextStyle(fontFeatures: ftAmountFeatures),
          decoration: InputDecoration(
            labelText: 'Saldo atual',
            hintText: '0,00',
            suffixText: _currency.symbol,
            helperText: 'Quanto tem hoje nesta conta. Pode deixar a zero.',
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

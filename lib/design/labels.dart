import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';

/// Nome da moeda em português.
String currencyName(Currency c) => switch (c.code) {
      'AOA' => 'Kwanza',
      'USD' => 'Dólar americano',
      'EUR' => 'Euro',
      'BRL' => 'Real brasileiro',
      'GBP' => 'Libra esterlina',
      'ZAR' => 'Rand sul-africano',
      _ => c.code,
    };

String accountTypeLabel(AccountType t) => switch (t) {
      AccountType.bank => 'Banco',
      AccountType.cash => 'Numerário',
      AccountType.mobileWallet => 'Carteira móvel',
      AccountType.card => 'Cartão',
      AccountType.savings => 'Poupança',
    };

/// Nome sugerido ao escolher o tipo, para poupar escrita.
String accountTypeDefaultName(AccountType t) => switch (t) {
      AccountType.bank => 'Conta à ordem',
      AccountType.cash => 'Carteira',
      AccountType.mobileWallet => 'Carteira móvel',
      AccountType.card => 'Cartão',
      AccountType.savings => 'Poupança',
    };

IconData accountTypeIcon(AccountType t) => switch (t) {
      AccountType.bank => Icons.account_balance_outlined,
      AccountType.cash => Icons.payments_outlined,
      AccountType.mobileWallet => Icons.smartphone_outlined,
      AccountType.card => Icons.credit_card_outlined,
      AccountType.savings => Icons.savings_outlined,
    };

String autoLockLabel(AutoLockSetting s) => switch (s) {
      AutoLockSetting.immediate => 'Imediatamente',
      AutoLockSetting.oneMinute => 'Após 1 minuto',
      AutoLockSetting.fiveMinutes => 'Após 5 minutos',
      AutoLockSetting.fifteenMinutes => 'Após 15 minutos',
    };

/// Valor formatado, ou oculto no modo discreto.
String amountText(Money m, {required bool discreet}) =>
    discreet ? '••••••' : m.format();

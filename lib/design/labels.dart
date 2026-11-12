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

IconData categoryIcon(String icon) => switch (icon) {
      'home' => Icons.home_outlined,
      'food' => Icons.restaurant_outlined,
      'transport' => Icons.directions_bus_outlined,
      'health' => Icons.local_hospital_outlined,
      'education' => Icons.school_outlined,
      'personal' => Icons.person_outline,
      'household' => Icons.cleaning_services_outlined,
      'debt' => Icons.receipt_long_outlined,
      'savings' => Icons.savings_outlined,
      'shield' => Icons.shield_outlined,
      'project' => Icons.construction_outlined,
      'family' => Icons.family_restroom_outlined,
      'group' => Icons.groups_outlined,
      'salary' => Icons.work_outline,
      'business' => Icons.storefront_outlined,
      'refund' => Icons.undo_outlined,
      'interest' => Icons.trending_up,
      _ => Icons.category_outlined,
    };

String movementKindLabel(MovementKind k) => switch (k) {
      MovementKind.income => 'Entrada',
      MovementKind.expense => 'Saída',
      MovementKind.transfer => 'Transferência',
    };

const _months = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

String monthName(int month) => _months[month - 1];

/// "Hoje", "Ontem" ou "12 de novembro de 2026".
String dayLabel(DateTime d, {DateTime? today}) {
  final t = today ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final ref = DateTime(t.year, t.month, t.day);
  if (day == ref) return 'Hoje';
  if (day == ref.subtract(const Duration(days: 1))) return 'Ontem';
  return '${d.day} de ${monthName(d.month)} de ${d.year}';
}

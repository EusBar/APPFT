import 'currency.dart';
import 'money.dart';
import 'names.dart';

/// Tipos de conta (secção 4): o dinheiro em Angola não vive só nos bancos.
enum AccountType {
  bank('bank'),
  cash('cash'),
  mobileWallet('mobile_wallet'),
  card('card'),
  savings('savings');

  const AccountType(this.code);

  /// Código guardado na base de dados; nunca muda.
  final String code;

  /// Poupança e investimento ficam fora do saldo disponível por defeito.
  bool get includedInAvailableByDefault => this != AccountType.savings;

  static AccountType fromCode(String code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    throw ArgumentError.value(code, 'code', 'Tipo de conta desconhecido');
  }
}

/// Conta do utilizador. A instituição é só organizacional: sem integração
/// bancária nem credenciais.
class Account {
  Account({
    required this.id,
    required this.type,
    required String name,
    String? institution,
    required this.openingBalance,
    required DateTime startDate,
    bool? includeInAvailable,
    this.archived = false,
  })  : name = _requireName(name),
        institution = _optionalInstitution(institution),
        startDate = DateTime(startDate.year, startDate.month, startDate.day),
        includeInAvailable =
            includeInAvailable ?? type.includedInAvailableByDefault;

  static const institutionMaxLength = 60;

  final String id;
  final AccountType type;
  final String name;
  final String? institution;

  /// Saldo na data de início, na moeda da conta.
  final Money openingBalance;

  /// Só a data conta; a hora é descartada.
  final DateTime startDate;
  final bool includeInAvailable;

  /// Contas com movimentos são arquivadas, nunca apagadas.
  final bool archived;

  Currency get currency => openingBalance.currency;

  static String _requireName(String name) {
    final clean = NameRules.clean(name);
    if (clean == null) {
      throw ArgumentError.value(name, 'name', 'Nome de conta inválido');
    }
    return clean;
  }

  static String? _optionalInstitution(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final clean = NameRules.clean(value, max: institutionMaxLength);
    if (clean == null) {
      throw ArgumentError.value(value, 'institution', 'Instituição inválida');
    }
    return clean;
  }
}

/// Somas de saldos por moeda. Moedas diferentes nunca se somam: sem taxa de
/// câmbio, os totais ficam separados (secção 5).
class Balances {
  /// Ainda não há movimentos: o saldo de cada conta é o saldo inicial.
  static Map<Currency, Money> byCurrency(
    Iterable<Account> accounts, {
    bool availableOnly = false,
  }) {
    final totals = <Currency, Money>{};
    for (final a in accounts) {
      if (a.archived) continue;
      if (availableOnly && !a.includeInAvailable) continue;
      totals[a.currency] =
          (totals[a.currency] ?? Money.zero(a.currency)) + a.openingBalance;
    }
    return totals;
  }
}

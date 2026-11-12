import 'account.dart';
import 'commitment.dart';
import 'currency.dart';
import 'ledger.dart';
import 'money.dart';
import 'movement.dart';

/// Resumo de uma conta num período.
class AccountPeriod {
  const AccountPeriod(this.account, this.opening, this.closing);
  final Account account;
  final Money opening;
  final Money closing;
}

/// Total de uma categoria no período.
class CategoryTotal {
  const CategoryTotal(this.categoryId, this.total);
  final String categoryId;
  final Money total;
}

/// Números de um período numa só moeda. Moedas nunca se misturam.
class CurrencyReport {
  CurrencyReport({
    required this.currency,
    required this.opening,
    required this.income,
    required this.expense,
    required this.transfersIn,
    required this.transfersOut,
    required this.closing,
    required this.incomeByCategory,
    required this.expenseByCategory,
    required this.accounts,
    required this.pendingCommitments,
  });

  final Currency currency;
  final Money opening;
  final Money income;
  final Money expense;
  final Money transfersIn;
  final Money transfersOut;
  final Money closing;
  final List<CategoryTotal> incomeByCategory;
  final List<CategoryTotal> expenseByCategory;
  final List<AccountPeriod> accounts;

  /// Compromissos pendentes no fim do período (apresentados em separado).
  final Money pendingCommitments;

  Money get net => income - expense;
}

/// Relatório de um período, gerado só pelo motor financeiro (secção 22).
class PeriodReport {
  PeriodReport._(this.from, this.to, this.currencies, this.movements, this.pending);

  final DateTime from;
  final DateTime to;
  final List<CurrencyReport> currencies;

  /// Movimentos em vigor no período, por data.
  final List<Movement> movements;

  /// Compromissos pendentes com data até ao fim do período.
  final List<Commitment> pending;

  static PeriodReport build(Ledger ledger, {required DateTime from, required DateTime to}) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) throw ArgumentError('Período inválido');

    final accounts = [
      for (final a in ledger.accounts.values)
        if (!a.startDate.isAfter(end)) a,
    ];
    final accountIds = {for (final a in accounts) a.id};

    Money balanceAt(Account a, DateTime day, {required bool inclusive}) {
      var minor = a.openingBalance.minor;
      for (final m in ledger.movements) {
        final within = inclusive ? !m.date.isAfter(day) : m.date.isBefore(day);
        if (within) minor += m.effectOn(a.id);
      }
      return Money(minor, a.currency);
    }

    bool inPeriod(Movement m) => !m.date.isBefore(start) && !m.date.isAfter(end);

    final currencies = <Currency>{for (final a in accounts) a.currency}.toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    final reports = <CurrencyReport>[];
    for (final c in currencies) {
      final curAccounts = [for (final a in accounts) if (a.currency == c) a];
      final ids = {for (final a in curAccounts) a.id};
      var opening = 0, closing = 0, income = 0, expense = 0, tin = 0, tout = 0;
      final periods = <AccountPeriod>[];
      for (final a in curAccounts) {
        // Conta aberta durante o período: o saldo inicial conta como abertura.
        final o = a.startDate.isAfter(start)
            ? a.openingBalance
            : balanceAt(a, start, inclusive: false);
        final cl = balanceAt(a, end, inclusive: true);
        opening += o.minor;
        closing += cl.minor;
        periods.add(AccountPeriod(a, o, cl));
      }
      final incomeCat = <String, int>{};
      final expenseCat = <String, int>{};
      for (final m in ledger.movements) {
        if (!inPeriod(m)) continue;
        final sign = m.isReversal ? -1 : 1;
        switch (m.kind) {
          case MovementKind.income:
            if (ids.contains(m.accountId)) {
              income += sign * m.amount.minor;
              incomeCat[m.categoryId!] = (incomeCat[m.categoryId!] ?? 0) + sign * m.amount.minor;
            }
          case MovementKind.expense:
            if (ids.contains(m.accountId)) {
              expense += sign * m.amount.minor;
              expenseCat[m.categoryId!] = (expenseCat[m.categoryId!] ?? 0) + sign * m.amount.minor;
            }
          case MovementKind.transfer:
            if (ids.contains(m.accountId)) tout += sign * m.amount.minor;
            if (ids.contains(m.toAccountId)) tin += sign * m.toAmount!.minor;
        }
      }
      List<CategoryTotal> sorted(Map<String, int> totals) => [
            for (final e in totals.entries)
              if (e.value != 0) CategoryTotal(e.key, Money(e.value, c)),
          ]..sort((a, b) => b.total.minor.compareTo(a.total.minor));

      var pendingMinor = 0;
      for (final p in ledger.pending()) {
        if (p.amount.currency == c && ids.contains(p.accountId) && !p.dueDate.isAfter(end)) {
          pendingMinor += p.amount.minor;
        }
      }

      reports.add(CurrencyReport(
        currency: c,
        opening: Money(opening, c),
        income: Money(income, c),
        expense: Money(expense, c),
        transfersIn: Money(tin, c),
        transfersOut: Money(tout, c),
        closing: Money(closing, c),
        incomeByCategory: sorted(incomeCat),
        expenseByCategory: sorted(expenseCat),
        accounts: periods,
        pendingCommitments: Money(pendingMinor, c),
      ));
    }

    final movements = [
      for (final m in ledger.active())
        if (inPeriod(m) && (accountIds.contains(m.accountId) || accountIds.contains(m.toAccountId))) m,
    ]..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
      });
    final pending = [
      for (final p in ledger.pending())
        if (!p.dueDate.isAfter(end) && accountIds.contains(p.accountId)) p,
    ];
    return PeriodReport._(start, end, reports, movements, pending);
  }
}

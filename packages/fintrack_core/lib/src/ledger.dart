import 'account.dart';
import 'currency.dart';
import 'money.dart';
import 'movement.dart';

/// Motivo pelo qual um movimento novo é recusado.
enum MovementIssue {
  unknownAccount,
  archivedAccount,
  currencyMismatch,
  beforeAccountStart,
  inFuture,
  unknownOriginal,
  alreadyReversed,
  reverseOfReversal,
}

/// Totais de um período, por moeda. Transferências próprias não contam.
class PeriodTotals {
  const PeriodTotals(this.income, this.expense);

  final Map<Currency, Money> income;
  final Map<Currency, Money> expense;
}

/// Livro-razão: a única fonte oficial de saldos (secção 9).
///
/// Os saldos calculam-se sempre a partir do saldo inicial e de todos os
/// registos, estornos incluídos; recalcular dá sempre o mesmo resultado.
class Ledger {
  Ledger(Iterable<Account> accounts, Iterable<Movement> movements)
      : accounts = {for (final a in accounts) a.id: a},
        movements = List.unmodifiable(movements) {
    for (final m in this.movements) {
      final original = m.reverses;
      if (original != null) _reversedBy[original] = m.id;
    }
  }

  final Map<String, Account> accounts;
  final List<Movement> movements;
  final Map<String, String> _reversedBy = {};

  bool isReversed(String id) => _reversedBy.containsKey(id);

  Movement? byId(String id) {
    for (final m in movements) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Movimentos em vigor: nem estornos nem estornados, mais recentes primeiro.
  List<Movement> active() {
    final list = [
      for (final m in movements)
        if (!m.isReversal && !isReversed(m.id)) m,
    ];
    list.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  Money balanceOf(String accountId) {
    final account = accounts[accountId];
    if (account == null) throw ArgumentError.value(accountId, 'accountId', 'Conta desconhecida');
    var minor = account.openingBalance.minor;
    for (final m in movements) {
      minor += m.effectOn(accountId);
    }
    return Money(minor, account.currency);
  }

  /// Saldos somados por moeda; moedas diferentes nunca se misturam.
  Map<Currency, Money> balances({bool availableOnly = false}) {
    final totals = <Currency, Money>{};
    for (final a in accounts.values) {
      if (a.archived) continue;
      if (availableOnly && !a.includeInAvailable) continue;
      totals[a.currency] = (totals[a.currency] ?? Money.zero(a.currency)) + balanceOf(a.id);
    }
    return totals;
  }

  /// Entradas e saídas com data entre [from] e [to], ambos incluídos.
  /// Um movimento estornado e o seu estorno anulam-se.
  PeriodTotals totals(DateTime from, DateTime to) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    final income = <Currency, Money>{};
    final expense = <Currency, Money>{};
    for (final m in movements) {
      if (m.kind == MovementKind.transfer) continue;
      if (m.date.isBefore(start) || m.date.isAfter(end)) continue;
      final target = m.kind == MovementKind.income ? income : expense;
      final c = m.amount.currency;
      final signed = m.isReversal ? -m.amount : m.amount;
      target[c] = (target[c] ?? Money.zero(c)) + signed;
    }
    income.removeWhere((_, v) => v.isZero);
    expense.removeWhere((_, v) => v.isZero);
    return PeriodTotals(income, expense);
  }

  /// Valida um movimento antes de gravar. Devolve `null` se for aceitável.
  MovementIssue? check(Movement m, {required DateTime today}) {
    final reverses = m.reverses;
    if (reverses != null) {
      final original = byId(reverses);
      if (original == null) return MovementIssue.unknownOriginal;
      if (original.isReversal) return MovementIssue.reverseOfReversal;
      if (isReversed(reverses)) return MovementIssue.alreadyReversed;
      return null;
    }

    final from = accounts[m.accountId];
    if (from == null) return MovementIssue.unknownAccount;
    if (from.archived) return MovementIssue.archivedAccount;
    if (m.amount.currency != from.currency) return MovementIssue.currencyMismatch;
    if (m.date.isBefore(from.startDate)) return MovementIssue.beforeAccountStart;

    final toId = m.toAccountId;
    if (toId != null) {
      final to = accounts[toId];
      if (to == null) return MovementIssue.unknownAccount;
      if (to.archived) return MovementIssue.archivedAccount;
      if (m.toAmount!.currency != to.currency) return MovementIssue.currencyMismatch;
      if (m.date.isBefore(to.startDate)) return MovementIssue.beforeAccountStart;
    }

    final lastDay = DateTime(today.year, today.month, today.day);
    if (m.date.isAfter(lastDay)) return MovementIssue.inFuture;

    final replaces = m.replaces;
    if (replaces != null) {
      final original = byId(replaces);
      if (original == null || original.isReversal) return MovementIssue.unknownOriginal;
      if (isReversed(replaces)) return MovementIssue.alreadyReversed;
    }
    return null;
  }

  /// Movimento em vigor muito parecido com [m] (mesma conta, tipo, valor e
  /// dia, descrição igual ou vazia): pede confirmação antes de gravar.
  Movement? possibleDuplicate(Movement m) {
    String norm(String s) => s.trim().toLowerCase();
    for (final other in active()) {
      if (other.id == m.id || other.id == m.replaces) continue;
      if (other.kind != m.kind ||
          other.accountId != m.accountId ||
          other.toAccountId != m.toAccountId ||
          other.amount != m.amount ||
          other.date != m.date) {
        continue;
      }
      final a = norm(other.description);
      final b = norm(m.description);
      if (a == b || a.isEmpty || b.isEmpty) return other;
    }
    return null;
  }
}

import 'account.dart';
import 'category.dart';
import 'commitment.dart';
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
  wrongCategory,
  notPending,
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
  Ledger(
    Iterable<Account> accounts,
    Iterable<Movement> movements, {
    Iterable<Commitment> commitments = const [],
  })  : accounts = {for (final a in accounts) a.id: a},
        movements = List.unmodifiable(movements),
        commitments = List.unmodifiable(commitments) {
    for (final m in this.movements) {
      final original = m.reverses;
      if (original != null) _reversedBy[original] = m.id;
      final replaced = m.replaces;
      if (replaced != null) _replacedBy[replaced] = m.id;
    }
  }

  final Map<String, Account> accounts;
  final List<Movement> movements;
  final List<Commitment> commitments;
  final Map<String, String> _reversedBy = {};
  final Map<String, String> _replacedBy = {};

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

  // --- Compromissos ---------------------------------------------------------

  /// Movimento em vigor que paga [c], seguindo correções (estorno + novo
  /// registo). `null` se nunca foi pago ou se o pagamento foi anulado.
  Movement? paymentOf(Commitment c) {
    var id = c.paidMovementId;
    while (id != null && isReversed(id)) {
      id = _replacedBy[id];
    }
    return id == null ? null : byId(id);
  }

  /// Estado efetivo. Um pagamento anulado devolve o compromisso a pendente,
  /// sem escrever nada: o livro-razão é a fonte da verdade.
  CommitmentStatus statusOf(Commitment c) {
    if (c.status != CommitmentStatus.paid) return c.status;
    return paymentOf(c) == null ? CommitmentStatus.pending : CommitmentStatus.paid;
  }

  /// Compromissos pendentes, por data prevista.
  List<Commitment> pending() {
    final list = [
      for (final c in commitments)
        if (statusOf(c) == CommitmentStatus.pending) c,
    ];
    list.sort((a, b) {
      final byDate = a.dueDate.compareTo(b.dueDate);
      return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  /// Total dos compromissos pendentes que reduzem o disponível até ao fim do
  /// horizonte (os atrasados incluídos), por moeda.
  Map<Currency, Money> committed({required DateTime today, required AvailableHorizon horizon}) {
    final end = horizon.end(today);
    final totals = <Currency, Money>{};
    for (final c in pending()) {
      if (c.dueDate.isAfter(end)) continue;
      final account = accounts[c.accountId];
      if (account == null || account.archived || !account.includeInAvailable) continue;
      final cur = c.amount.currency;
      totals[cur] = (totals[cur] ?? Money.zero(cur)) + c.amount;
    }
    return totals;
  }

  /// Saldo disponível = saldos das contas incluídas − compromissos pendentes
  /// até ao horizonte. Por moeda: sem taxa de câmbio, nunca se misturam.
  Map<Currency, Money> available({required DateTime today, required AvailableHorizon horizon}) {
    final totals = Map.of(balances(availableOnly: true));
    committed(today: today, horizon: horizon).forEach((cur, amount) {
      totals[cur] = (totals[cur] ?? Money.zero(cur)) - amount;
    });
    return totals;
  }

  /// Valida um compromisso novo ou editado (só pendentes se editam).
  MovementIssue? checkCommitment(Commitment c, {Category? category}) {
    final account = accounts[c.accountId];
    if (account == null) return MovementIssue.unknownAccount;
    if (account.archived) return MovementIssue.archivedAccount;
    if (c.amount.currency != account.currency) return MovementIssue.currencyMismatch;
    if (category != null && category.kind != CategoryKind.expense) {
      return MovementIssue.wrongCategory;
    }
    if (c.status != CommitmentStatus.pending) return MovementIssue.notPending;
    return null;
  }

  /// Saída que paga [c] na data [date]. Valida-se com [check] antes de gravar.
  Movement paymentFor(
    Commitment c, {
    required String id,
    required DateTime date,
    required DateTime createdAt,
  }) {
    if (statusOf(c) != CommitmentStatus.pending) {
      throw StateError('Só se pagam compromissos pendentes');
    }
    return Movement(
      id: id,
      kind: MovementKind.expense,
      accountId: c.accountId,
      amount: c.amount,
      categoryId: c.categoryId,
      description: c.description,
      date: date,
      origin: MovementOrigin.commitment,
      createdAt: createdAt,
    );
  }

  // --- Contas -----------------------------------------------------------------

  /// A conta tem algum registo no livro-razão (como origem ou destino).
  bool hasMovements(String accountId) =>
      movements.any((m) => m.accountId == accountId || m.toAccountId == accountId);

  bool hasCommitments(String accountId) => commitments.any((c) => c.accountId == accountId);

  /// Apagar só sem movimentos nem compromissos: o histórico nunca muda.
  bool canDelete(String accountId) =>
      !hasMovements(accountId) && !hasCommitments(accountId) && _otherOpen(accountId);

  /// O saldo inicial só se corrige enquanto não houver movimentos.
  bool canEditOpening(String accountId) => !hasMovements(accountId);

  /// Arquivar exige que não fiquem compromissos pendentes nessa conta e que
  /// reste pelo menos uma conta ativa.
  bool canArchive(String accountId) =>
      _otherOpen(accountId) && !pending().any((c) => c.accountId == accountId);

  bool _otherOpen(String accountId) =>
      accounts.values.any((a) => a.id != accountId && !a.archived);

  // --- Importações ------------------------------------------------------------

  /// Lotes de importação com registos ainda em vigor, do mais recente.
  Map<String, List<Movement>> importBatches() {
    final batches = <String, List<Movement>>{};
    for (final m in movements) {
      final b = m.batchId;
      if (b == null || m.isReversal || isReversed(m.id)) continue;
      (batches[b] ??= []).add(m);
    }
    final ordered = batches.entries.toList()
      ..sort((a, b) => b.value.first.createdAt.compareTo(a.value.first.createdAt));
    return {for (final e in ordered) e.key: e.value};
  }
}

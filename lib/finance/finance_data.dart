import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../security/session.dart';

/// Tudo o que os ecrãs precisam, lido da base cifrada. O livro-razão é a
/// única fonte dos valores mostrados.
class FinanceData {
  FinanceData({
    required List<Account> accounts,
    required this.categories,
    required List<Movement> movements,
    List<Commitment> commitments = const [],
  }) : ledger = Ledger(accounts, movements, commitments: commitments);

  final List<Category> categories;
  final Ledger ledger;

  late final Map<String, Category> _categoryById = {for (final c in categories) c.id: c};

  List<Account> get accounts => ledger.accounts.values.toList();
  List<Account> get openAccounts => [for (final a in accounts) if (!a.archived) a];
  List<Account> get archivedAccounts => [for (final a in accounts) if (a.archived) a];

  Category? category(String? id) => id == null ? null : _categoryById[id];
  Account? account(String? id) => id == null ? null : ledger.accounts[id];
}

/// Recarrega quando a sessão muda ou depois de `ref.invalidate`.
final financeProvider = FutureProvider.autoDispose<FinanceData>((ref) async {
  ref.watch(sessionProvider.select((s) => s.status));
  final store = ref.read(sessionProvider.notifier).store;
  if (store == null) {
    return FinanceData(accounts: const [], categories: const [], movements: const []);
  }
  final accounts = await store.accounts();
  final categories = await store.categories();
  final movements = await store.movements();
  final commitments = await store.commitments();
  return FinanceData(
    accounts: accounts,
    categories: categories,
    movements: movements,
    commitments: commitments,
  );
});

/// Operações de escrita no livro-razão. Validam com o motor antes de gravar.
class LedgerWriter {
  LedgerWriter(this._store, this._data);

  final LocalStore _store;
  final FinanceData _data;

  /// Grava um movimento novo, ou a correção de [m.replaces] (estorno do
  /// original + registo novo, numa única transação).
  Future<MovementIssue?> save(Movement m, {DateTime? today}) async {
    final ledger = _data.ledger;
    final issue = ledger.check(m, today: today ?? DateTime.now());
    if (issue != null) return issue;
    final replaces = m.replaces;
    if (replaces == null) {
      await _store.append([m]);
    } else {
      final original = ledger.byId(replaces)!;
      await _store.append([
        original.reversal(id: newId(), createdAt: DateTime.now()),
        m,
      ]);
    }
    return null;
  }

  /// Cria ou altera um compromisso pendente.
  Future<MovementIssue?> saveCommitment(Commitment c) async {
    final issue = _data.ledger.checkCommitment(c, category: _data.category(c.categoryId));
    if (issue != null) return issue;
    await _store.saveCommitment(c);
    return null;
  }

  /// Paga um compromisso: gera a saída ligada, na data indicada.
  Future<MovementIssue?> payCommitment(Commitment c, {required DateTime date}) async {
    final ledger = _data.ledger;
    if (ledger.statusOf(c) != CommitmentStatus.pending) return MovementIssue.notPending;
    final payment = ledger.paymentFor(c, id: newId(), date: date, createdAt: DateTime.now());
    final issue = ledger.check(payment, today: DateTime.now());
    if (issue != null) return issue;
    await _store.payCommitment(c, payment);
    return null;
  }

  Future<MovementIssue?> cancelCommitment(Commitment c) async {
    if (_data.ledger.statusOf(c) != CommitmentStatus.pending) return MovementIssue.notPending;
    await _store.cancelCommitment(c.id);
    return null;
  }

  /// Anula um movimento com um estorno.
  Future<MovementIssue?> cancel(Movement original) async {
    final r = original.reversal(id: newId(), createdAt: DateTime.now());
    final issue = _data.ledger.check(r, today: DateTime.now());
    if (issue != null) return issue;
    await _store.append([r]);
    return null;
  }
}

String movementIssueMessage(MovementIssue issue) => switch (issue) {
      MovementIssue.unknownAccount => 'Escolha uma conta válida.',
      MovementIssue.archivedAccount => 'Esta conta está arquivada.',
      MovementIssue.currencyMismatch => 'A moeda não corresponde à da conta.',
      MovementIssue.beforeAccountStart =>
        'A data é anterior ao início da conta no FINTRACK.',
      MovementIssue.inFuture =>
        'A data está no futuro. Pagamentos previstos chegam com os compromissos.',
      MovementIssue.unknownOriginal => 'O movimento original já não existe.',
      MovementIssue.alreadyReversed => 'Este movimento já foi anulado.',
      MovementIssue.reverseOfReversal => 'Um estorno não pode ser anulado.',
      MovementIssue.wrongCategory => 'Escolha uma categoria de despesa.',
      MovementIssue.notPending => 'Este compromisso já não está pendente.',
    };

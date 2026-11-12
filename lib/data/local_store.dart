import 'dart:typed_data';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Perfil do utilizador neste dispositivo.
class Profile {
  const Profile({required this.name, required this.mainCurrency});

  final String name;
  final Currency mainCurrency;
}

/// Dados locais do FINTRACK, abertos só depois do desbloqueio.
abstract interface class LocalStore {
  Future<Profile?> loadProfile();

  /// Grava o perfil e a primeira conta numa única transação.
  Future<void> completeOnboarding(Profile profile, Account firstAccount);

  Future<List<Account>> accounts();

  Future<void> addAccount(Account account);

  Future<List<Category>> categories();

  /// Todos os registos do livro-razão, estornos incluídos.
  Future<List<Movement>> movements();

  /// Acrescenta registos numa única transação (ex.: estorno + correção).
  /// Os registos nunca se alteram nem se apagam.
  Future<void> append(List<Movement> records);

  Future<List<Commitment>> commitments();

  /// Cria ou altera um compromisso pendente.
  Future<void> saveCommitment(Commitment commitment);

  /// Grava a saída e marca o compromisso como pago, numa única transação.
  Future<void> payCommitment(Commitment commitment, Movement payment);

  Future<void> cancelCommitment(String id);

  Future<void> close();
}

/// Abre a base de dados com a chave libertada pelo PIN.
abstract interface class LocalStoreFactory {
  Future<LocalStore> open(Uint8List dataKey);

  /// Apaga a base de dados deste dispositivo.
  Future<void> wipe();
}

/// Implementação em memória, só para testes.
@visibleForTesting
class MemoryLocalStore implements LocalStore, LocalStoreFactory {
  Profile? profile;
  final List<Account> stored = [];
  final List<Movement> ledger = [];
  final Map<String, Commitment> commitmentsById = {};
  Uint8List? openedWith;
  bool closed = false;

  @override
  Future<LocalStore> open(Uint8List dataKey) async {
    openedWith = Uint8List.fromList(dataKey);
    closed = false;
    return this;
  }

  @override
  Future<void> wipe() async {
    profile = null;
    stored.clear();
    ledger.clear();
    commitmentsById.clear();
  }

  @override
  Future<Profile?> loadProfile() async => profile;

  @override
  Future<void> completeOnboarding(Profile profile, Account firstAccount) async {
    this.profile = profile;
    stored.add(firstAccount);
  }

  @override
  Future<List<Account>> accounts() async => List.unmodifiable(stored);

  @override
  Future<void> addAccount(Account account) async => stored.add(account);

  @override
  Future<List<Category>> categories() async => Category.defaults;

  @override
  Future<List<Movement>> movements() async => List.unmodifiable(ledger);

  @override
  Future<void> append(List<Movement> records) async {
    final ids = ledger.map((m) => m.id).toSet();
    for (final r in records) {
      if (!ids.add(r.id)) throw StateError('Registo duplicado: ${r.id}');
    }
    ledger.addAll(records);
  }

  @override
  Future<List<Commitment>> commitments() async => commitmentsById.values.toList();

  @override
  Future<void> saveCommitment(Commitment commitment) async {
    if (commitment.status != CommitmentStatus.pending) {
      throw StateError('Só se gravam compromissos pendentes');
    }
    commitmentsById[commitment.id] = commitment;
  }

  @override
  Future<void> payCommitment(Commitment commitment, Movement payment) async {
    await append([payment]);
    commitmentsById[commitment.id] =
        commitment.copyWith(status: CommitmentStatus.paid, paidMovementId: payment.id);
  }

  @override
  Future<void> cancelCommitment(String id) async {
    final c = commitmentsById[id];
    if (c != null) {
      commitmentsById[id] = Commitment(
        id: c.id,
        accountId: c.accountId,
        amount: c.amount,
        categoryId: c.categoryId,
        description: c.description,
        note: c.note,
        dueDate: c.dueDate,
        status: CommitmentStatus.cancelled,
        createdAt: c.createdAt,
      );
    }
  }

  @override
  Future<void> close() async => closed = true;
}

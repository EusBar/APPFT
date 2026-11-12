import 'dart:typed_data';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/foundation.dart';

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
  Future<void> close() async => closed = true;
}

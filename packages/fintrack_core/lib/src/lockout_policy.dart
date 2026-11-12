/// Atrasos progressivos após tentativas falhadas de PIN (secção 3).
class LockoutPolicy {
  /// Após este número de falhas, exige novo início de sessão na conta.
  static const maxAttempts = 10;

  /// Tempo de espera obrigatório depois de [failures] falhas seguidas.
  static Duration delayAfter(int failures) {
    if (failures < 3) return Duration.zero;
    switch (failures) {
      case 3:
        return const Duration(seconds: 30);
      case 4:
        return const Duration(minutes: 1);
      case 5:
        return const Duration(minutes: 5);
      case 6:
        return const Duration(minutes: 15);
      case 7:
        return const Duration(minutes: 30);
      default:
        return const Duration(hours: 1);
    }
  }

  static bool requiresAccountSignIn(int failures) => failures >= maxAttempts;
}

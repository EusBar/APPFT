/// Opções de bloqueio automático em segundo plano (secção 3).
enum AutoLockSetting {
  immediate(Duration.zero),
  oneMinute(Duration(minutes: 1)),
  fiveMinutes(Duration(minutes: 5)),
  fifteenMinutes(Duration(minutes: 15));

  const AutoLockSetting(this.timeout);

  final Duration timeout;
}

class AutoLockPolicy {
  /// Decide se o app deve bloquear ao voltar do segundo plano.
  ///
  /// Se o relógio andou para trás, bloqueia sempre.
  static bool shouldLock({
    required DateTime backgroundedAt,
    required DateTime now,
    required AutoLockSetting setting,
  }) {
    final elapsed = now.difference(backgroundedAt);
    if (elapsed.isNegative) return true;
    return elapsed >= setting.timeout;
  }
}

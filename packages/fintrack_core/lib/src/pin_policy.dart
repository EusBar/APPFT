/// Motivo pelo qual um PIN é recusado.
enum PinIssue {
  /// Não tem exatamente 6 caracteres.
  length,

  /// Contém caracteres que não são algarismos.
  notDigits,

  /// Todos os algarismos iguais (000000).
  allSame,

  /// Sequência crescente ou decrescente (123456, 654321).
  sequential,

  /// Padrão repetido (121212, 123123).
  repeatedPattern,

  /// Parece uma data (DDMMAA ou AAMMDD).
  date,
}

/// Regras do PIN de 6 dígitos (secção 3 do Prompt Master).
class PinPolicy {
  static const length = 6;

  static const _daysInMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  /// Devolve `null` se o PIN for aceitável, ou o motivo da recusa.
  static PinIssue? check(String pin) {
    if (pin.length != length) return PinIssue.length;
    final units = pin.codeUnits;
    if (units.any((u) => u < 0x30 || u > 0x39)) return PinIssue.notDigits;
    final d = [for (final u in units) u - 0x30];

    if (d.every((x) => x == d[0])) return PinIssue.allSame;

    final diffs = [for (var i = 0; i < 5; i++) (d[i + 1] - d[i]) % 10];
    if (diffs.every((x) => x == 1) || diffs.every((x) => x == 9)) {
      return PinIssue.sequential;
    }

    if (pin == pin.substring(0, 2) * 3 || pin == pin.substring(0, 3) * 2) {
      return PinIssue.repeatedPattern;
    }

    final a = d[0] * 10 + d[1];
    final b = d[2] * 10 + d[3];
    final c = d[4] * 10 + d[5];
    if (_isDayMonth(a, b) || _isDayMonth(c, b)) return PinIssue.date;

    return null;
  }

  static bool isAcceptable(String pin) => check(pin) == null;

  static bool _isDayMonth(int day, int month) =>
      month >= 1 && month <= 12 && day >= 1 && day <= _daysInMonth[month - 1];
}

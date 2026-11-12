import 'currency.dart';

/// Valor monetário guardado em inteiros na unidade mínima da moeda.
///
/// Nunca usa vírgula flutuante: 12 500,00 Kz = 1 250 000 cêntimos.
class Money implements Comparable<Money> {
  const Money(this.minor, this.currency);

  const Money.zero(this.currency) : minor = 0;

  /// Valor na unidade mínima (ex.: cêntimos).
  final int minor;
  final Currency currency;

  static const _nbsp = ' ';
  static final _spaces = RegExp(r'[\s  ]');
  static final _digits = RegExp(r'^\d+$');

  /// Interpreta o texto escrito pelo utilizador no formato local.
  ///
  /// A vírgula é o separador decimal; espaços e pontos agrupam milhares.
  /// Sem vírgula, um único ponto seguido de 1 ou 2 algarismos conta como
  /// decimal ("12.5"); seguido de 3 algarismos conta como milhares ("12.500").
  /// Mais casas decimais do que a moeda permite dá erro, nunca arredonda.
  static Money parse(String input, Currency currency) {
    var s = input.replaceAll(_spaces, '');
    if (s.isEmpty) throw const FormatException('Valor vazio');

    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    }

    String intPart;
    var fracPart = '';
    if (s.contains(',')) {
      final parts = s.split(',');
      if (parts.length != 2) throw FormatException('Valor inválido', input);
      intPart = parts[0].replaceAll('.', '');
      fracPart = parts[1];
    } else if ('.'.allMatches(s).length == 1) {
      final i = s.indexOf('.');
      final after = s.substring(i + 1);
      if (after.length == 3) {
        intPart = s.replaceAll('.', '');
      } else {
        intPart = s.substring(0, i);
        fracPart = after;
      }
    } else {
      intPart = s.replaceAll('.', '');
    }

    if (intPart.isEmpty && fracPart.isNotEmpty) intPart = '0';
    if (!_digits.hasMatch(intPart) || intPart.length > 15) {
      throw FormatException('Valor inválido', input);
    }
    if (fracPart.isNotEmpty && !_digits.hasMatch(fracPart)) {
      throw FormatException('Valor inválido', input);
    }
    if (fracPart.length > currency.minorUnits) {
      throw FormatException('Casas decimais a mais para ${currency.code}', input);
    }

    final frac = fracPart.padRight(currency.minorUnits, '0');
    final minor =
        int.parse(intPart) * currency.factor + (frac.isEmpty ? 0 : int.parse(frac));
    return Money(negative ? -minor : minor, currency);
  }

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;

  Money operator +(Money other) {
    _sameCurrency(other);
    return Money(minor + other.minor, currency);
  }

  Money operator -(Money other) {
    _sameCurrency(other);
    return Money(minor - other.minor, currency);
  }

  Money operator -() => Money(-minor, currency);

  /// Moedas diferentes nunca se somam sem conversão explícita.
  void _sameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'Moedas diferentes: ${currency.code} e ${other.currency.code}',
      );
    }
  }

  @override
  int compareTo(Money other) {
    _sameCurrency(other);
    return minor.compareTo(other.minor);
  }

  /// Formato local: `1 234 567,89 Kz` (espaços não separáveis).
  String format({bool withSymbol = true}) {
    final f = currency.factor;
    final a = minor.abs();
    final whole = (a ~/ f).toString();
    final buf = StringBuffer();
    if (minor < 0) buf.write('-');
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write(_nbsp);
      buf.write(whole[i]);
    }
    if (currency.minorUnits > 0) {
      buf
        ..write(',')
        ..write((a % f).toString().padLeft(currency.minorUnits, '0'));
    }
    if (withSymbol) {
      buf
        ..write(_nbsp)
        ..write(currency.symbol);
    }
    return buf.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => '$minor ${currency.code} (unidade mínima)';
}

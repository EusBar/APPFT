/// Moeda ISO 4217 com o número de casas decimais da unidade mínima.
class Currency {
  const Currency(this.code, this.minorUnits, this.symbol);

  /// Código ISO 4217 (ex.: AOA).
  final String code;

  /// Casas decimais da unidade mínima (ex.: 2 para cêntimos).
  final int minorUnits;

  /// Símbolo apresentado ao utilizador (ex.: Kz).
  final String symbol;

  /// Quantas unidades mínimas compõem uma unidade (ex.: 100).
  int get factor {
    var f = 1;
    for (var i = 0; i < minorUnits; i++) {
      f *= 10;
    }
    return f;
  }

  static const aoa = Currency('AOA', 2, 'Kz');
  static const usd = Currency('USD', 2, r'US$');
  static const eur = Currency('EUR', 2, '€');
  static const brl = Currency('BRL', 2, r'R$');
  static const gbp = Currency('GBP', 2, '£');
  static const zar = Currency('ZAR', 2, 'R');

  /// Moedas suportadas no lançamento (secção 5 do Prompt Master).
  static const supported = <Currency>[aoa, usd, eur, brl, gbp, zar];

  static Currency fromCode(String code) {
    final upper = code.toUpperCase();
    for (final c in supported) {
      if (c.code == upper) return c;
    }
    throw ArgumentError.value(code, 'code', 'Moeda não suportada');
  }

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// Regra de ouro (secção 13): cada número numa resposta da IA tem de existir
/// nos resultados do motor obtidos nesse pedido. Números sem origem
/// verificável bloqueiam a resposta.
class NumberValidator {
  NumberValidator(Iterable<Object?> engineResults) {
    for (final r in engineResults) {
      _collect(r);
    }
  }

  /// Valores aceites, em duas formas: inteiro e "unidades mínimas" (×100).
  final Set<int> _allowed = {};

  /// Números pequenos que não são valores (ex.: "3 categorias", "dia 5").
  static const smallLimit = 31;

  void _collect(Object? v) {
    if (v == null) return;
    if (v is int) {
      _allow(v);
    } else if (v is double) {
      _allow((v * 100).round(), minor: true);
      _allow(v.round());
    } else if (v is String) {
      for (final n in extract(v)) {
        _allowParsed(n);
      }
    } else if (v is Map) {
      v.values.forEach(_collect);
    } else if (v is Iterable) {
      v.forEach(_collect);
    }
  }

  void _allow(int v, {bool minor = false}) {
    _allowed.add(v.abs());
    if (!minor) _allowed.add(v.abs() * 100);
  }

  void _allowParsed(String token) {
    for (final c in candidates(token)) {
      _allowed.add(c);
    }
  }

  static final _number = RegExp(r'-?\d[\d   .,]*\d|-?\d');

  /// Números escritos num texto, como aparecem.
  static List<String> extract(String text) =>
      [for (final m in _number.allMatches(text)) m.group(0)!.trim()];

  /// Interpretações possíveis de um número escrito (em inteiros e em
  /// unidades mínimas): "12 500,50" -> 1250050; "12.500" -> 12500 e 1250000.
  static Set<int> candidates(String token) {
    final t = token.replaceAll(RegExp(r'[\s  ]'), '').replaceAll('-', '');
    final out = <int>{};
    void add(String intPart, String frac) {
      final i = int.tryParse(intPart.isEmpty ? '0' : intPart);
      if (i == null) return;
      final f = int.tryParse((frac + '00').substring(0, 2)) ?? 0;
      out.add(i * 100 + f);
      if (frac.isEmpty || int.tryParse(frac) == 0) {
        out.add(i);
      }
    }

    if (t.contains(',')) {
      final parts = t.split(',');
      add(parts.first.replaceAll('.', ''), parts.length > 1 ? parts[1] : '');
    } else if ('.'.allMatches(t).length == 1 && t.split('.')[1].length != 3) {
      final parts = t.split('.');
      add(parts[0], parts[1]);
    } else {
      add(t.replaceAll('.', ''), '');
    }
    return out;
  }

  /// Números do texto sem origem no motor. Vazio = resposta aceite.
  /// Inteiros simples até 31 (dias, contagens) e anos não são valores.
  List<String> unverified(String answer) {
    final bad = <String>[];
    for (final token in extract(answer)) {
      final plain = int.tryParse(token.replaceFirst('-', ''));
      if (plain != null && (plain <= smallLimit || (plain >= 2000 && plain <= 2100))) continue;
      final c = candidates(token);
      if (c.isEmpty) continue;
      if (!c.any(_allowed.contains)) bad.add(token);
    }
    return bad;
  }

  bool accepts(String answer) => unverified(answer).isEmpty;
}

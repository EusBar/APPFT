/// Regras para nomes escritos pelo utilizador (perfil, contas).
class NameRules {
  static const maxLength = 40;
  static final _spaces = RegExp(r'\s+');

  /// Tira espaços a mais. Devolve `null` se ficar vazio ou longo demais.
  static String? clean(String input, {int max = maxLength}) {
    final s = input.trim().replaceAll(_spaces, ' ');
    if (s.isEmpty || s.length > max) return null;
    return s;
  }
}

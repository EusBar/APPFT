import 'money.dart';
import 'movement.dart';

/// Exportação de movimentos em CSV (separador ";", decimais com vírgula),
/// pronto a abrir no Excel em português.
class MovementCsv {
  static const header = [
    'Data', 'Tipo', 'Descrição', 'Categoria', 'Conta', 'Valor', 'Moeda',
    'Conta de destino', 'Valor recebido', 'Moeda recebida', 'Observações', 'Origem', 'ID',
  ];

  /// Valor sem separadores de milhares: 1234567,89.
  static String plain(Money m) {
    final f = m.currency.factor;
    final a = m.minor.abs();
    final sign = m.minor < 0 ? '-' : '';
    if (m.currency.minorUnits == 0) return '$sign$a';
    return '$sign${a ~/ f},${(a % f).toString().padLeft(m.currency.minorUnits, '0')}';
  }

  static String _cell(String v) {
    // Evita fórmulas ao abrir no Excel (injeção em CSV).
    var s = v;
    if (s.isNotEmpty && '=+-@'.contains(s[0]) && double.tryParse(s.replaceAll(',', '.')) == null) {
      s = "'$s";
    }
    if (s.contains(RegExp(r'[;"\n\r]'))) return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String encode(
    Iterable<Movement> movements, {
    required String Function(String? categoryId) categoryName,
    required String Function(String? accountId) accountName,
    required String Function(MovementKind kind) kindName,
  }) {
    final rows = <List<String>>[header];
    for (final m in movements) {
      rows.add([
        _date(m.date),
        kindName(m.kind),
        m.description,
        m.categoryId == null ? '' : categoryName(m.categoryId),
        accountName(m.accountId),
        plain(m.amount),
        m.amount.currency.code,
        m.toAccountId == null ? '' : accountName(m.toAccountId),
        m.toAmount == null ? '' : plain(m.toAmount!),
        m.toAmount?.currency.code ?? '',
        m.note,
        m.origin.code,
        m.id,
      ]);
    }
    return '${rows.map((r) => r.map(_cell).join(';')).join('\r\n')}\r\n';
  }
}

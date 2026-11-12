import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Lê a primeira folha de um ficheiro Excel (.xlsx) como linhas de texto.
///
/// Números com casas decimais saem com ponto e 2 casas (ex.: "12500.50"),
/// para o motor os interpretar sem ambiguidade; inteiros saem como estão
/// (as datas do Excel são números de série inteiros).
class XlsxReader {
  static List<List<String>> read(List<int> bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('Ficheiro Excel inválido');
    }

    String? text(String path) {
      final f = zip.findFile(path);
      return f == null ? null : utf8.decode(f.content, allowMalformed: true);
    }

    final shared = <String>[];
    final sharedXml = text('xl/sharedStrings.xml');
    if (sharedXml != null) {
      for (final si in XmlDocument.parse(sharedXml).findAllElements('si')) {
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }

    final sheetXml = text(_firstSheetPath(text) ?? 'xl/worksheets/sheet1.xml');
    if (sheetXml == null) throw const FormatException('Folha não encontrada');

    final rows = <List<String>>[];
    for (final row in XmlDocument.parse(sheetXml).findAllElements('row')) {
      final cells = <int, String>{};
      var next = 0;
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? next : _columnIndex(ref);
        next = col + 1;
        final type = c.getAttribute('t');
        final v = c.getElement('v')?.innerText ?? '';
        cells[col] = switch (type) {
          's' => shared.elementAtOrNull(int.tryParse(v) ?? -1) ?? '',
          'inlineStr' => c.findAllElements('t').map((t) => t.innerText).join(),
          'str' || 'b' || 'e' => v,
          _ => _number(v),
        };
      }
      if (cells.isEmpty) continue;
      final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
      final values = [for (var i = 0; i < width; i++) (cells[i] ?? '').trim()];
      if (values.any((v) => v.isNotEmpty)) rows.add(values);
    }
    return rows;
  }

  static String _number(String v) {
    if (v.isEmpty) return v;
    final d = double.tryParse(v);
    if (d == null) return v;
    if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
    return d.toStringAsFixed(2);
  }

  /// "AB12" -> 27 (A = 0).
  static int _columnIndex(String ref) {
    var n = 0;
    for (final unit in ref.codeUnits) {
      if (unit < 65 || unit > 90) break;
      n = n * 26 + (unit - 64);
    }
    return n - 1;
  }

  static String? _firstSheetPath(String? Function(String) text) {
    final workbook = text('xl/workbook.xml');
    final rels = text('xl/_rels/workbook.xml.rels');
    if (workbook == null || rels == null) return null;
    final sheet = XmlDocument.parse(workbook).findAllElements('sheet').firstOrNull;
    final rid = sheet?.attributes
        .where((a) => a.name.local == 'id')
        .map((a) => a.value)
        .firstOrNull;
    if (rid == null) return null;
    for (final rel in XmlDocument.parse(rels).findAllElements('Relationship')) {
      if (rel.getAttribute('Id') == rid) {
        final target = rel.getAttribute('Target') ?? '';
        return target.startsWith('/') ? target.substring(1) : 'xl/$target';
      }
    }
    return null;
  }
}

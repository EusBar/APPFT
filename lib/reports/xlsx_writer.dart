import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Estilo de uma célula no ficheiro Excel.
enum XStyle {
  normal(0),
  bold(1),
  money(2),
  moneyBold(3),
  header(4),
  percent(5),
  title(6),
  muted(7),
  moneyIncome(8),
  moneyExpense(9),
  section(10),
  date(11);

  const XStyle(this.id);
  final int id;
}

/// Uma célula: texto, número ou data, com estilo.
class XCell {
  const XCell.text(String this.text, [this.style = XStyle.normal]) : number = null;
  const XCell.number(double this.number, [this.style = XStyle.money]) : text = null;
  XCell.date(DateTime d, [this.style = XStyle.date])
      : text = null,
        number = d.difference(DateTime(1899, 12, 30)).inDays.toDouble();
  const XCell.empty()
      : text = null,
        number = null,
        style = XStyle.normal;

  final String? text;
  final double? number;
  final XStyle style;
}

class XSheet {
  XSheet(String name, {this.widths = const []}) : name = _safeName(name);

  final String name;

  /// Largura de cada coluna, em caracteres.
  final List<double> widths;
  final List<List<XCell>> rows = [];

  void add(List<XCell> row) => rows.add(row);
  void blank() => rows.add(const []);

  static String _safeName(String s) {
    final clean = s.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ').trim();
    return clean.length > 31 ? clean.substring(0, 31) : clean;
  }
}

/// Gerador mínimo de ficheiros .xlsx (Office Open XML), sem dependências
/// além do zip. Abre no Excel, Google Sheets, Numbers e LibreOffice.
class XlsxWriter {
  static Uint8List build(List<XSheet> sheets) {
    final archive = Archive();
    void add(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add('[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join('\n')}
</Types>''');
    add('_rels/.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');
    add('xl/workbook.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>
${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join('\n')}
</sheets>
</workbook>''');
    add('xl/_rels/workbook.xml.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${[for (var i = 1; i <= sheets.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join('\n')}
<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''');
    add('xl/styles.xml', _styles);
    for (var i = 0; i < sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheet(sheets[i]));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  // Formatos: 164 = dinheiro com separador de milhares e 2 casas,
  // 165 = percentagem com 1 casa, 166 = data dd/mm/aaaa.
  static const _styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="3">
<numFmt numFmtId="164" formatCode="#,##0.00"/>
<numFmt numFmtId="165" formatCode="0.0%"/>
<numFmt numFmtId="166" formatCode="dd/mm/yyyy"/>
</numFmts>
<fonts count="7">
<font><sz val="11"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
<font><b/><sz val="16"/><color rgb="FF0F766E"/><name val="Calibri"/></font>
<font><sz val="10"/><color rgb="FF64748B"/><name val="Calibri"/></font>
<font><sz val="11"/><color rgb="FF059669"/><name val="Calibri"/></font>
<font><sz val="11"/><color rgb="FFDC2626"/><name val="Calibri"/></font>
</fonts>
<fills count="4">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF0F766E"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFF0FDFA"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="2">
<border><left/><right/><top/><bottom/><diagonal/></border>
<border><left/><right/><top style="thin"><color rgb="FF94A3B8"/></top><bottom/><diagonal/></border>
</borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="12">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="164" fontId="1" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/>
<xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
<xf numFmtId="165" fontId="4" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="164" fontId="5" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
<xf numFmtId="164" fontId="6" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
<xf numFmtId="0" fontId="1" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
<xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
</cellXfs>
</styleSheet>''';

  static String _sheet(XSheet s) {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    if (s.widths.isNotEmpty) {
      b.write('<cols>');
      for (var i = 0; i < s.widths.length; i++) {
        b.write('<col min="${i + 1}" max="${i + 1}" width="${s.widths[i]}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < s.rows.length; r++) {
      final row = s.rows[r];
      b.write('<row r="${r + 1}">');
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        final ref = '${_col(c)}${r + 1}';
        if (cell.number != null) {
          b.write('<c r="$ref" s="${cell.style.id}"><v>${cell.number}</v></c>');
        } else if (cell.text != null) {
          b.write('<c r="$ref" s="${cell.style.id}" t="inlineStr"><is><t xml:space="preserve">${_esc(cell.text!)}</t></is></c>');
        } else if (cell.style != XStyle.normal) {
          b.write('<c r="$ref" s="${cell.style.id}"/>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  static String _col(int i) {
    var n = i + 1;
    final out = StringBuffer();
    while (n > 0) {
      final m = (n - 1) % 26;
      out.write(String.fromCharCode(65 + m));
      n = (n - 1) ~/ 26;
    }
    return out.toString().split('').reversed.join();
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
}

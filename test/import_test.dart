import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:fintrack/importing/import_screen.dart';
import 'package:fintrack/importing/xlsx_reader.dart';
import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monta um .xlsx mínimo, como o Excel grava: textos partilhados, números
/// e uma data como número de série.
List<int> buildXlsx() {
  final archive = Archive()
    ..addFile(ArchiveFile.string('xl/workbook.xml', '''<?xml version="1.0"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="Folha1" sheetId="1" r:id="rId1"/></sheets></workbook>'''))
    ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', '''<?xml version="1.0"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/></Relationships>'''))
    ..addFile(ArchiveFile.string('xl/sharedStrings.xml', '''<?xml version="1.0"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<si><t>Data</t></si><si><t>Descrição</t></si><si><t>Valor</t></si><si><t>Mercado</t></si>
<si><r><t>Sal</t></r><r><t>ário</t></r></si></sst>'''))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', '''<?xml version="1.0"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>
<row r="2"><c r="A2"><v>46329</v></c><c r="B2" t="s"><v>3</v></c><c r="C2"><v>-12500.5</v></c></row>
<row r="3"><c r="A3"><v>46330</v></c><c r="B3" t="s"><v>4</v></c><c r="C3"><v>300000</v></c></row>
<row r="4"><c r="C4"><v>0.30000000000000004</v></c></row>
</sheetData></worksheet>'''));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  test('lê a primeira folha de um .xlsx', () {
    final rows = XlsxReader.read(buildXlsx());
    expect(rows[0], ['Data', 'Descrição', 'Valor']);
    expect(rows[1], ['46329', 'Mercado', '-12500.50']);
    expect(rows[2], ['46330', 'Salário', '300000']);
    expect(rows[3], ['', '', '0.30']);
  });

  test('do Excel ao plano de importação', () {
    final rows = XlsxReader.read(buildXlsx()).take(3).toList();
    final account = Account(
      id: 'a',
      type: AccountType.bank,
      name: 'BAI',
      openingBalance: const Money(0, Currency.aoa),
      startDate: DateTime(2026, 1, 1),
    );
    var n = 0;
    final plan = ImportPlan.build(
      rows: rows,
      hasHeader: true,
      columns: ImportColumns.guess(rows.first),
      account: account,
      categories: Category.defaults,
      ledger: Ledger([account], []),
      today: DateTime(2026, 11, 12),
      batchId: 'b',
      newId: () => 'm${n++}',
      now: () => DateTime(2026, 11, 12),
    );
    expect(plan[0].movement!.date, DateTime(2026, 11, 3));
    expect(plan[0].movement!.amount, const Money(1250050, Currency.aoa));
    expect(plan[0].movement!.kind, MovementKind.expense);
    expect(plan[1].movement!.kind, MovementKind.income);
  });

  test('ficheiro que não é Excel dá erro de formato', () {
    expect(() => XlsxReader.read(utf8.encode('não é um zip')), throwsFormatException);
  });

  test('texto em Latin-1 (CSV do Excel no Windows)', () {
    expect(decodeText(latin1.encode('Descrição;Pão')), 'Descrição;Pão');
    expect(decodeText(utf8.encode('Descrição;Pão')), 'Descrição;Pão');
  });
}

import 'dart:typed_data';

import 'package:fintrack_core/fintrack_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../design/labels.dart';

/// Caracteres que a fonte padrão do PDF (WinAnsi) consegue desenhar.
const _winAnsiExtras = '€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ';

/// Troca o que a fonte não desenha por equivalentes seguros.
String pdfSafe(String s) {
  final buf = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    if (r == 0x2212) {
      buf.write('-');
    } else if (r == 0x2192) {
      buf.write('->');
    } else if (r < 256 || _winAnsiExtras.contains(ch)) {
      buf.write(ch);
    } else {
      buf.write('?');
    }
  }
  return buf.toString();
}

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// Relatório mensal em A4 (secção 22). Todos os números vêm do motor.
Future<Uint8List> buildReportPdf({
  required PeriodReport report,
  required String ownerName,
  required String Function(String? categoryId) categoryName,
  required String Function(String? accountId) accountName,
  DateTime? generatedAt,
}) async {
  final doc = pw.Document(title: 'FINTRACK — Relatório', author: pdfSafe(ownerName));
  final now = generatedAt ?? DateTime.now();
  const teal = PdfColor.fromInt(0xFF0F766E);
  const grey = PdfColor.fromInt(0xFF64748B);
  const line = PdfColor.fromInt(0xFFE2E8F0);
  final small = pw.TextStyle(fontSize: 8, color: grey);
  final body = const pw.TextStyle(fontSize: 9);
  final bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);

  pw.Widget t(String s, {pw.TextStyle? style, pw.TextAlign? align}) =>
      pw.Text(pdfSafe(s), style: style ?? body, textAlign: align);

  pw.Widget section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(
          pdfSafe(title.toUpperCase()),
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: teal, letterSpacing: 1),
        ),
      );

  pw.Widget kv(String k, Money v, {bool strong = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.Expanded(child: t(k, style: strong ? bold : body)),
          t(v.format(), style: strong ? bold : body),
        ]),
      );

  pw.Widget table(List<String> headers, List<List<String>> rows, {Set<int> right = const {}}) {
    return pw.TableHelper.fromTextArray(
      headers: [for (final h in headers) pdfSafe(h)],
      data: [for (final r in rows) [for (final c in r) pdfSafe(c)]],
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: grey),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: line)),
      ),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.5)),
      ),
      border: null,
      cellAlignments: {for (final i in right) i: pw.Alignment.centerRight},
      headerAlignments: {for (final i in right) i: pw.Alignment.centerRight},
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
    );
  }

  final period = '${_date(report.from)} a ${_date(report.to)}';

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 40),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line))),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('FINTRACK',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: teal, letterSpacing: 2)),
                pw.Text('Your Money. Under Control.', style: small),
              ],
            ),
            pw.Spacer(),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                t('Relatório financeiro · ${pdfSafe(ownerName)}', style: bold),
                t('Período: $period', style: small),
                t('Gerado em ${_date(now)} às ${_two(now.hour)}:${_two(now.minute)}', style: small),
              ],
            ),
          ],
        ),
      ),
      footer: (context) => pw.Column(
        children: [
          pw.Divider(color: line, height: 8),
          pw.Row(children: [
            pw.Expanded(
              child: t(
                'Relatório elaborado com base nos movimentos financeiros registados manualmente no FINTRACK.',
                style: small,
              ),
            ),
            t('Página ${context.pageNumber} de ${context.pagesCount}', style: small),
          ]),
        ],
      ),
      build: (context) => [
        for (final c in report.currencies) ...[
          section('Resumo · ${c.currency.code}'),
          kv('Saldo inicial', c.opening),
          kv('Entradas', c.income),
          kv('Saídas', c.expense),
          kv('Transferências recebidas', c.transfersIn),
          kv('Transferências enviadas', c.transfersOut),
          pw.Divider(color: line, height: 6),
          kv('Saldo final', c.closing, strong: true),
          kv('Resultado do período (entradas - saídas)', c.net, strong: true),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFFFFBEB),
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Row(children: [
              pw.Expanded(child: t('Compromissos pendentes (não incluídos no saldo final)')),
              t(c.pendingCommitments.format(), style: bold),
            ]),
          ),
          if (c.expenseByCategory.isNotEmpty) ...[
            section('Saídas por categoria · ${c.currency.code}'),
            table(
              ['Categoria', 'Valor', '%'],
              [
                for (final x in c.expenseByCategory)
                  [
                    categoryName(x.categoryId),
                    x.total.format(),
                    c.expense.minor == 0 ? '' : '${(x.total.minor * 100) ~/ c.expense.minor}%',
                  ],
              ],
              right: {1, 2},
            ),
          ],
          if (c.incomeByCategory.isNotEmpty) ...[
            section('Entradas por categoria · ${c.currency.code}'),
            table(
              ['Categoria', 'Valor'],
              [for (final x in c.incomeByCategory) [categoryName(x.categoryId), x.total.format()]],
              right: {1},
            ),
          ],
          section('Por conta · ${c.currency.code}'),
          table(
            ['Conta', 'Saldo inicial', 'Saldo final'],
            [for (final a in c.accounts) [a.account.name, a.opening.format(), a.closing.format()]],
            right: {1, 2},
          ),
        ],
        if (report.pending.isNotEmpty) ...[
          section('Compromissos pendentes'),
          table(
            ['Data prevista', 'Descrição', 'Conta', 'Valor'],
            [
              for (final p in report.pending)
                [_date(p.dueDate), p.description, accountName(p.accountId), p.amount.format()],
            ],
            right: {3},
          ),
        ],
        section('Movimentos'),
        if (report.movements.isEmpty)
          t('Sem movimentos no período.', style: small)
        else
          table(
            ['Data', 'Tipo', 'Descrição', 'Categoria / Destino', 'Conta', 'Valor'],
            [
              for (final m in report.movements)
                [
                  _date(m.date),
                  movementKindLabel(m.kind),
                  m.description,
                  m.kind == MovementKind.transfer ? '-> ${accountName(m.toAccountId)}' : categoryName(m.categoryId),
                  accountName(m.accountId),
                  '${m.kind == MovementKind.expense ? '-' : m.kind == MovementKind.income ? '+' : ''}${m.amount.format()}',
                ],
            ],
            right: {5},
          ),
      ],
    ),
  );
  return doc.save();
}

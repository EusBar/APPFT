import 'dart:math' as math;
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
String _short(DateTime d) => '${_two(d.day)}/${_two(d.month)}';

/// Percentagem com uma casa decimal, arredondada a meio para cima ("85,9%").
String percentOf(int part, int total) {
  if (total <= 0) return '';
  final tenths = (part * 1000 + total ~/ 2) ~/ total;
  return '${tenths ~/ 10},${tenths % 10}%';
}

// Cores do modelo (iguais às do app).
const _teal = PdfColor.fromInt(0xFF0F766E);
const _tealDark = PdfColor.fromInt(0xFF115E59);
const _text = PdfColor.fromInt(0xFF1F2933);
const _muted = PdfColor.fromInt(0xFF64748B);
const _card = PdfColor.fromInt(0xFFF5F7FA);
const _line = PdfColor.fromInt(0xFFE5E9F0);
const _income = PdfColor.fromInt(0xFF059669);
const _expense = PdfColor.fromInt(0xFFDC2626);
const _insightBg = PdfColor.fromInt(0xFFF0FDFA);
const _insightLine = PdfColor.fromInt(0xFF99F6E4);
const _palette = [
  PdfColor.fromInt(0xFF7C5CFF),
  PdfColor.fromInt(0xFF14B8A6),
  PdfColor.fromInt(0xFFF59E0B),
  PdfColor.fromInt(0xFFEF4444),
  PdfColor.fromInt(0xFF3B82F6),
  PdfColor.fromInt(0xFFEC4899),
  PdfColor.fromInt(0xFF84CC16),
  PdfColor.fromInt(0xFF94A3B8),
];

/// Relatório do período em A4: o modelo oficial do FINTRACK. Todos os
/// números vêm do motor (livro-razão); nada é estimado.
Future<Uint8List> buildReportPdf({
  required PeriodReport report,
  required String ownerName,
  required String Function(String? categoryId) categoryName,
  required String Function(String? accountId) accountName,
  DateTime? generatedAt,
}) async {
  final doc = pw.Document(title: 'FINTRACK — Relatório', author: pdfSafe(ownerName));
  final now = generatedAt ?? DateTime.now();
  final days = DateTime(report.to.year, report.to.month, report.to.day)
          .difference(DateTime(report.from.year, report.from.month, report.from.day))
          .inDays +
      1;

  pw.TextStyle st(double size, {PdfColor color = _text, bool bold = false, double spacing = 0}) => pw.TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        letterSpacing: spacing,
      );
  pw.Widget t(String s, pw.TextStyle style, {pw.TextAlign? align}) => pw.Text(pdfSafe(s), style: style, textAlign: align);
  pw.Widget card(pw.Widget child, {pw.EdgeInsets padding = const pw.EdgeInsets.all(10)}) => pw.Container(
        padding: padding,
        decoration: pw.BoxDecoration(
          color: _card,
          border: pw.Border.all(color: _line, width: 0.8),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: child,
      );
  pw.Widget section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
        child: t(title.toUpperCase(), st(8.5, color: _teal, bold: true, spacing: 1.2)),
      );

  // Período em texto: "1 a 16 de novembro de 2026".
  final sameMonth = report.from.year == report.to.year && report.from.month == report.to.month;
  final periodText = sameMonth
      ? '${report.from.day} a ${report.to.day} de ${monthName(report.to.month).toLowerCase()} de ${report.to.year}'
      : '${_date(report.from)} a ${_date(report.to)}';

  // Movimentos por ordem cronológica e saldo de cada conta depois de cada um.
  final movements = [...report.movements]..sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.createdAt.compareTo(b.createdAt);
    });
  final running = <String, int>{
    for (final c in report.currencies)
      for (final a in c.accounts) a.account.id: a.opening.minor,
  };
  final balanceAfter = <String, Money>{};
  for (final m in movements) {
    final cur = running[m.accountId];
    if (cur == null) continue;
    running[m.accountId] = cur + m.effectOn(m.accountId);
    final dest = m.toAccountId;
    if (dest != null && running[dest] != null) running[dest] = running[dest]! + m.effectOn(dest);
    balanceAfter[m.id] = Money(running[m.accountId]!, m.amount.currency);
  }

  final blocks = <pw.Widget>[];
  for (final c in report.currencies) {
    final cur = c.currency;
    final multi = report.currencies.length > 1;
    final suffix = multi ? ' · ${cur.code}' : '';
    final expense = c.expense.minor;

    // --- Cartões de resumo ---------------------------------------------------
    final delta = c.opening.minor == 0
        ? null
        : '${((c.closing.minor - c.opening.minor) * 100 / c.opening.minor).round() >= 0 ? '+' : ''}'
            '${((c.closing.minor - c.opening.minor) * 100 / c.opening.minor).round()}% face ao inicial';
    pw.Widget kpi(String label, Money v, PdfColor color, {String? sub}) => pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 0),
            child: card(
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                t(label, st(7.5, color: _muted)),
                pw.SizedBox(height: 2),
                t(v.format(), st(10.5, color: color, bold: true)),
                if (sub != null) t(sub, st(6.5, color: c.closing.minor < c.opening.minor ? _expense : _income)),
              ]),
              padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 7),
            ),
          ),
        );
    blocks.add(pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      kpi('Saldo inicial', c.opening, _text),
      pw.SizedBox(width: 6),
      kpi('Entradas', c.income, _income),
      pw.SizedBox(width: 6),
      kpi('Saídas', c.expense, _expense),
      pw.SizedBox(width: 6),
      kpi('Saldo final', c.closing, _teal, sub: delta),
    ]));

    // --- O essencial do período --------------------------------------------
    final insights = <List<pw.TextSpan>>[];
    pw.TextSpan n(String s) => pw.TextSpan(text: pdfSafe(s));
    pw.TextSpan b(String s) => pw.TextSpan(text: pdfSafe(s), style: pw.TextStyle(fontWeight: pw.FontWeight.bold));
    if (c.expenseByCategory.isNotEmpty && expense > 0) {
      final top = c.expenseByCategory.first;
      final inTop = [
        for (final m in movements)
          if (m.kind == MovementKind.expense && m.categoryId == top.categoryId && m.amount.currency == cur) m,
      ];
      insights.add([
        b(categoryName(top.categoryId)),
        n(' representa '),
        b(percentOf(top.total.minor, expense)),
        n(' das saídas do período'),
        n(inTop.length == 1 ? ': um único movimento de ${top.total.format()}.' : ' (${inTop.length} movimentos).'),
      ]);
    }
    if (c.opening.minor > 0 && expense > 0) {
      final used = (expense * 100 / c.opening.minor).round();
      insights.add([
        n('Gastou '),
        b('$used%'),
        n(' do saldo com que começou o período. '),
        n(sameMonth
            ? 'Restam ${c.closing.format()} até ao fim de ${monthName(report.to.month).toLowerCase()}.'
            : 'Saldo no fim do período: ${c.closing.format()}.'),
      ]);
    }
    if (c.income.minor == 0) {
      insights.add([n('Sem entradas registadas no período. Registe o salário para ver a sua taxa de poupança.')]);
    } else {
      final rate = ((c.income.minor - expense) * 100 / c.income.minor).round();
      insights.add(rate >= 0
          ? [n('Poupou '), b('$rate%'), n(' do que recebeu no período.')]
          : [n('Gastou mais do que recebeu: '), b(c.net.format()), n(' no período.')]);
    }
    if (c.pendingCommitments.minor > 0) {
      insights.add([n('Há '), b(c.pendingCommitments.format()), n(' em compromissos por pagar, ainda não descontados.')]);
    }
    blocks.add(pw.SizedBox(height: 10));
    blocks.add(pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 8),
      decoration: pw.BoxDecoration(
        color: _insightBg,
        border: pw.Border.all(color: _insightLine, width: 0.8),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(children: [
          pw.Container(width: 6, height: 6, decoration: const pw.BoxDecoration(color: _teal, shape: pw.BoxShape.circle)),
          pw.SizedBox(width: 5),
          t('O ESSENCIAL DO PERÍODO$suffix', st(8.5, color: _teal, bold: true, spacing: 1.2)),
        ]),
        pw.SizedBox(height: 5),
        for (final spans in insights)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Container(
                width: 3.5,
                height: 3.5,
                margin: const pw.EdgeInsets.only(top: 3.5, right: 6),
                decoration: const pw.BoxDecoration(color: _text, shape: pw.BoxShape.circle),
              ),
              pw.Expanded(child: pw.RichText(text: pw.TextSpan(style: st(8.5), children: spans))),
            ]),
          ),
      ]),
    ));

    // --- Para onde foi o dinheiro --------------------------------------------
    if (c.expenseByCategory.isNotEmpty && expense > 0) {
      final cats = c.expenseByCategory;
      blocks.add(section('Para onde foi o dinheiro$suffix'));
      blocks.add(card(
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.SizedBox(
            width: 92,
            height: 92,
            child: pw.Stack(alignment: pw.Alignment.center, children: [
              pw.CustomPaint(
                size: const PdfPoint(92, 92),
                painter: (canvas, size) {
                  final cx = size.x / 2, cy = size.y / 2, r = size.x / 2;
                  var a = math.pi / 2; // começa no topo (y para cima no PDF)
                  for (var i = 0; i < cats.length; i++) {
                    final sweep = 2 * math.pi * cats[i].total.minor / expense;
                    canvas
                      ..setFillColor(_palette[i % _palette.length])
                      ..moveTo(cx, cy);
                    final steps = math.max(2, (sweep / 0.05).ceil());
                    for (var s = 0; s <= steps; s++) {
                      final ang = a - sweep * s / steps; // sentido dos ponteiros
                      canvas.lineTo(cx + r * math.cos(ang), cy + r * math.sin(ang));
                    }
                    canvas
                      ..closePath()
                      ..fillPath();
                    a -= sweep;
                  }
                  canvas
                    ..setFillColor(_card)
                    ..drawEllipse(cx, cy, r * 0.62, r * 0.62)
                    ..fillPath();
                },
              ),
              pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
                t('Saídas', st(6, color: _muted)),
                t(c.expense.format(withSymbol: false), st(8, bold: true)),
              ]),
            ]),
          ),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(children: [
              for (var i = 0; i < cats.length; i++)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
                  decoration: i == cats.length - 1
                      ? null
                      : const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6))),
                  child: pw.Row(children: [
                    pw.Container(
                      width: 7,
                      height: 7,
                      decoration: pw.BoxDecoration(
                        color: _palette[i % _palette.length],
                        borderRadius: pw.BorderRadius.circular(2),
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(child: t(categoryName(cats[i].categoryId), st(8.5))),
                    t(cats[i].total.format(), st(8.5, bold: true)),
                    pw.SizedBox(width: 10),
                    pw.SizedBox(
                      width: 34,
                      child: t(percentOf(cats[i].total.minor, expense), st(8.5, color: _muted), align: pw.TextAlign.right),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      ));
    }

    if (c.incomeByCategory.isNotEmpty) {
      blocks.add(section('De onde veio o dinheiro$suffix'));
      blocks.add(card(pw.Column(children: [
        for (final x in c.incomeByCategory)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(children: [
              pw.Expanded(child: t(categoryName(x.categoryId), st(8.5))),
              t(x.total.format(), st(8.5, color: _income, bold: true)),
              pw.SizedBox(width: 10),
              pw.SizedBox(
                width: 34,
                child: t(percentOf(x.total.minor, c.income.minor), st(8.5, color: _muted), align: pw.TextAlign.right),
              ),
            ]),
          ),
      ])));
    }

    // --- Contas ------------------------------------------------------------------
    blocks.add(section('Contas$suffix'));
    blocks.add(card(pw.Column(children: [
      for (final a in c.accounts)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.Expanded(child: t(a.account.name, st(8.5))),
            t('Inicial ${a.opening.format()}  ->  ', st(8.5, color: _muted)),
            t('Final ${a.closing.format()}', st(9, bold: true)),
          ]),
        ),
    ])));
  }

  // --- Movimentos (todas as moedas) --------------------------------------------------
  blocks.add(section('Movimentos (${movements.length})'));
  if (movements.isEmpty) {
    blocks.add(card(t('Sem movimentos no período.', st(8.5, color: _muted))));
  } else {
    pw.Widget head(String s, {bool right = false}) =>
        t(s.toUpperCase(), st(6.5, color: _muted, spacing: 0.8), align: right ? pw.TextAlign.right : null);
    final rows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: _card, border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6))),
        children: [
          pw.Padding(padding: const pw.EdgeInsets.fromLTRB(6, 7, 6, 5), child: head('Data')),
          pw.Padding(padding: const pw.EdgeInsets.fromLTRB(6, 7, 6, 5), child: head('Descrição')),
          pw.Padding(padding: const pw.EdgeInsets.fromLTRB(6, 7, 6, 5), child: head('Valor', right: true)),
          pw.Padding(padding: const pw.EdgeInsets.fromLTRB(6, 7, 6, 5), child: head('Saldo após', right: true)),
        ],
      ),
    ];
    for (final m in movements) {
      final kind = m.kind;
      final sign = kind == MovementKind.expense ? '-' : kind == MovementKind.income ? '+' : '';
      final color = kind == MovementKind.expense ? _expense : kind == MovementKind.income ? _income : _text;
      final title = m.description.isNotEmpty
          ? m.description
          : kind == MovementKind.transfer
              ? 'Transferência'
              : categoryName(m.categoryId);
      final detail = kind == MovementKind.transfer
          ? '${accountName(m.accountId)} -> ${accountName(m.toAccountId)}'
          : '${categoryName(m.categoryId)} · ${accountName(m.accountId)}';
      final after = balanceAfter[m.id];
      rows.add(pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.top,
        decoration: const pw.BoxDecoration(color: _card, border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6))),
        children: [
          pw.Padding(padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5), child: t(_short(m.date), st(8.5))),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              t(title, st(8.5, bold: true)),
              t(detail, st(7, color: _muted)),
            ]),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5),
            child: t('$sign${m.amount.format()}', st(8.5, color: color, bold: true), align: pw.TextAlign.right),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5),
            child: t(after?.format() ?? '', st(8.5, color: _muted), align: pw.TextAlign.right),
          ),
        ],
      ));
    }
    // Tabela solta (não dentro de um cartão): continua na página seguinte.
    blocks.add(pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(42),
        1: pw.FlexColumnWidth(),
        2: pw.FixedColumnWidth(92),
        3: pw.FixedColumnWidth(92),
      },
      border: const pw.TableBorder(
        left: pw.BorderSide(color: _line, width: 0.8),
        right: pw.BorderSide(color: _line, width: 0.8),
        top: pw.BorderSide(color: _line, width: 0.8),
      ),
      children: rows,
    ));
  }

  // --- Compromissos pendentes ---------------------------------------------------------
  blocks.add(pw.SizedBox(height: 8));
  if (report.pending.isEmpty) {
    blocks.add(card(pw.Row(children: [
      pw.Expanded(child: t('Compromissos pendentes até ao fim do período', st(8.5))),
      t(Money.zero(report.currencies.isEmpty ? Currency.aoa : report.currencies.first.currency).format(), st(9, bold: true)),
    ])));
  } else {
    blocks.add(section('Compromissos pendentes (${report.pending.length})'));
    blocks.add(card(pw.Column(children: [
      for (final p in report.pending)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.SizedBox(width: 40, child: t(_short(p.dueDate), st(8.5))),
            pw.Expanded(child: t('${p.description} · ${accountName(p.accountId)}', st(8.5))),
            t(p.amount.format(), st(8.5, bold: true)),
          ]),
        ),
    ])));
  }

  // --- Indicadores ---------------------------------------------------------------------
  final expenses = [for (final m in movements) if (m.kind == MovementKind.expense) m];
  if (report.currencies.length == 1 && movements.isNotEmpty) {
    final c = report.currencies.first;
    final biggest = expenses.isEmpty ? null : expenses.reduce((a, b) => b.amount.minor > a.amount.minor ? b : a);
    final spendDays = {for (final m in expenses) m.date}.length;
    pw.Widget ind(String label, String value, String sub) => pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 0),
            child: card(
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                t(label, st(6.5, color: _muted)),
                pw.SizedBox(height: 2),
                t(value, st(11, bold: true)),
                t(sub, st(6.5, color: _muted), align: pw.TextAlign.left),
              ]),
              padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
            ),
          ),
        );
    blocks.add(section('Indicadores'));
    blocks.add(pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        ind('Movimentos', '${movements.length}', 'no período'),
        pw.SizedBox(width: 6),
        ind('Média diária de saídas', Money((c.expense.minor * 2 + days) ~/ (2 * days), c.currency).format(),
            '$days ${days == 1 ? 'dia' : 'dias'}'),
        pw.SizedBox(width: 6),
        ind(
          'Maior saída',
          biggest?.amount.format() ?? Money.zero(c.currency).format(),
          biggest == null
              ? 'sem saídas'
              : (biggest.description.isNotEmpty ? biggest.description : categoryName(biggest.categoryId)),
        ),
        pw.SizedBox(width: 6),
        ind('Dias com gastos', '$spendDays', 'de $days'),
      ]));
  }

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40),
        // Faixa verde do cabeçalho, de ponta a ponta (só na primeira página).
        buildBackground: (context) => context.pageNumber == 1
            ? pw.FullPage(
                ignoreMargins: true,
                child: pw.Align(
                  alignment: pw.Alignment.topCenter,
                  child: pw.Container(
                    height: 74,
                    decoration: const pw.BoxDecoration(
                      gradient: pw.LinearGradient(
                        colors: [_teal, _tealDark],
                        begin: pw.Alignment.topLeft,
                        end: pw.Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
              )
            : pw.SizedBox(),
      ),
      header: (context) => context.pageNumber > 1
          ? pw.Padding(
              padding: const pw.EdgeInsets.only(top: 24, bottom: 10),
              child: pw.Row(children: [
                pw.Text('FINTRACK', style: st(9, color: _teal, bold: true, spacing: 2)),
                pw.Spacer(),
                t('Relatório financeiro · $ownerName · $periodText', st(7.5, color: _muted)),
              ]),
            )
          : pw.Container(
        height: 74,
        alignment: pw.Alignment.centerLeft,
        margin: const pw.EdgeInsets.only(bottom: 16),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Container(
            width: 24,
            height: 24,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Text('F', style: st(13, bold: true)),
          ),
          pw.SizedBox(width: 8),
          pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('FINTRACK', style: st(12, color: PdfColors.white, bold: true, spacing: 2.5)),
            t('O seu dinheiro, claro e seguro.', st(7, color: const PdfColor.fromInt(0xFFCCFBF1))),
          ]),
          pw.Spacer(),
          pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            t('Relatório financeiro · $ownerName', st(9, color: PdfColors.white, bold: true)),
            t(periodText, st(7.5, color: PdfColors.white)),
            t(
              'Gerado a ${_date(now)}, ${_two(now.hour)}:${_two(now.minute)}'
              '${report.currencies.length == 1 ? ' · Moeda: ${report.currencies.first.currency.code}' : ''}',
              st(7.5, color: PdfColors.white),
            ),
          ]),
        ]),
      ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.fromLTRB(0, 10, 0, 22),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 0.6))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              t(
                'Valores calculados a partir dos movimentos registados no FINTRACK. Não é um extrato bancário.',
                st(6.5, color: _muted),
              ),
              pw.RichText(
                text: pw.TextSpan(style: st(6.5, color: _muted), children: [
                  const pw.TextSpan(text: 'Gerado com o '),
                  pw.TextSpan(text: 'FINTRACK', style: st(6.5, color: _teal, bold: true)),
                  const pw.TextSpan(text: ' · eusbar.github.io/APPFT'),
                ]),
              ),
            ]),
          ),
          t('Página ${context.pageNumber} de ${context.pagesCount}', st(6.5, color: _muted)),
        ]),
      ),
      build: (context) => blocks,
    ),
  );
  return doc.save();
}

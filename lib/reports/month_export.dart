import 'dart:typed_data';

import 'package:fintrack_core/fintrack_core.dart';

import '../design/labels.dart';
import 'xlsx_writer.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _d(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Nome curto de um mês financeiro ("Nov 2026").
String shortMonthLabel(FinancialMonth m) => '${_cap(monthName(m.month).substring(0, 3))} ${m.year}';

/// Nome completo ("Novembro de 2026").
String monthLabel(FinancialMonth m) => '${_cap(monthName(m.month))} de ${m.year}';

/// Datas do período ("25/10/2026 a 24/11/2026").
String monthRange(FinancialMonth m) => '${_d(m.from)} a ${_d(m.to)}';

/// Descrição do mês financeiro em uso.
String cycleLabel(MonthCycle c) =>
    c.isCalendar ? 'Mês de calendário (dia 1 ao último dia)' : 'Começa no dia ${c.startDay} de cada mês';

double _major(Money m) => m.minor / m.currency.factor;

/// Livro Excel com o resumo dos [months] (por ordem cronológica).
///
/// Com mais de um mês, a primeira folha é o resumo anual (categorias × meses);
/// depois, uma folha por mês com totais por categoria e todos os movimentos.
/// Os valores vêm do livro-razão; o ficheiro é só uma fotografia legível.
Uint8List buildMonthsWorkbook({
  required Ledger ledger,
  required List<FinancialMonth> months,
  required MonthCycle cycle,
  required String Function(String? categoryId) categoryName,
  required String Function(String? accountId) accountName,
  required DateTime today,
  String? ownerName,
}) {
  final t = DateTime(today.year, today.month, today.day);
  PeriodReport reportOf(FinancialMonth m) =>
      PeriodReport.build(ledger, from: m.from, to: m.to.isAfter(t) && !m.from.isAfter(t) ? t : m.to);
  final reports = {for (final m in months) m: reportOf(m)};
  final sheets = <XSheet>[];

  // --- Resumo anual -----------------------------------------------------------
  if (months.length > 1) {
    final first = months.first, last = months.last;
    final title = first.year == last.year ? 'Resumo anual ${first.year}' : 'Resumo ${shortMonthLabel(first)} a ${shortMonthLabel(last)}';
    final s = XSheet(first.year == last.year ? 'Resumo ${first.year}' : 'Resumo', widths: [
      30,
      for (var i = 0; i < months.length; i++) 14,
      16,
    ]);
    s.add([XCell.text('FINTRACK · $title', XStyle.title)]);
    s.add([
      XCell.text(
        '${ownerName == null ? '' : '$ownerName · '}${cycleLabel(cycle)} · gerado a ${_d(t)}',
        XStyle.muted,
      ),
    ]);
    final currencies = <Currency>{
      for (final r in reports.values)
        for (final c in r.currencies) c.currency,
    };
    for (final cur in currencies) {
      CurrencyReport? cr(FinancialMonth m) => reports[m]!.currencies.where((c) => c.currency == cur).firstOrNull;
      s.blank();
      s.add([
        XCell.text(currencies.length > 1 ? 'Categoria (${cur.code})' : 'Categoria', XStyle.header),
        for (final m in months) XCell.text(shortMonthLabel(m), XStyle.header),
        const XCell.text('Total', XStyle.header),
      ]);

      void block(String title, List<CategoryTotal> Function(CurrencyReport) pick, Money Function(CurrencyReport) total,
          XStyle valueStyle) {
        s.add([XCell.text(title, XStyle.section), for (var i = 0; i <= months.length; i++) const XCell.text('', XStyle.section)]);
        final ids = <String>[];
        for (final m in months) {
          final c = cr(m);
          if (c == null) continue;
          for (final x in pick(c)) {
            if (!ids.contains(x.categoryId)) ids.add(x.categoryId);
          }
        }
        for (final id in ids) {
          var sum = 0.0;
          s.add([
            XCell.text(categoryName(id)),
            for (final m in months)
              () {
                final v = cr(m) == null
                    ? 0.0
                    : pick(cr(m)!).where((x) => x.categoryId == id).fold(0.0, (a, x) => a + _major(x.total));
                sum += v;
                return v == 0 ? const XCell.empty() : XCell.number(v, valueStyle);
              }(),
            XCell.number(sum, XStyle.moneyBold),
          ]);
        }
        var grand = 0.0;
        s.add([
          XCell.text('Total ${title.toLowerCase()}', XStyle.bold),
          for (final m in months)
            () {
              final v = cr(m) == null ? 0.0 : _major(total(cr(m)!));
              grand += v;
              return XCell.number(v, XStyle.moneyBold);
            }(),
          XCell.number(grand, XStyle.moneyBold),
        ]);
      }

      block('Entradas', (c) => c.incomeByCategory, (c) => c.income, XStyle.moneyIncome);
      s.blank();
      block('Saídas', (c) => c.expenseByCategory, (c) => c.expense, XStyle.moneyExpense);
      s.blank();
      var net = 0.0;
      s.add([
        const XCell.text('Saldo do mês (entradas - saídas)', XStyle.bold),
        for (final m in months)
          () {
            final v = cr(m) == null ? 0.0 : _major(cr(m)!.net);
            net += v;
            return XCell.number(v, XStyle.moneyBold);
          }(),
        XCell.number(net, XStyle.moneyBold),
      ]);
      s.add([
        const XCell.text('Saldo no fim do mês', XStyle.muted),
        for (final m in months) cr(m) == null ? const XCell.empty() : XCell.number(_major(cr(m)!.closing)),
      ]);
    }
    sheets.add(s);
  }

  // --- Uma folha por mês ------------------------------------------------------------
  for (final m in months.reversed) {
    final report = reports[m]!;
    final s = XSheet(shortMonthLabel(m), widths: const [34, 16, 12, 26, 22, 14]);
    s.add([XCell.text(monthLabel(m), XStyle.title)]);
    s.add([XCell.text('${monthRange(m)} · ${cycleLabel(cycle)}', XStyle.muted)]);
    for (final c in report.currencies) {
      final multi = report.currencies.length > 1;
      s.blank();
      s.add([XCell.text(multi ? 'Resumo (${c.currency.code})' : 'Resumo', XStyle.header), const XCell.text('', XStyle.header)]);
      s.add([const XCell.text('Saldo inicial'), XCell.number(_major(c.opening))]);
      s.add([const XCell.text('Entradas'), XCell.number(_major(c.income), XStyle.moneyIncome)]);
      s.add([const XCell.text('Saídas'), XCell.number(_major(c.expense), XStyle.moneyExpense)]);
      if (!c.transfersIn.isZero || !c.transfersOut.isZero) {
        s.add([const XCell.text('Transferências recebidas'), XCell.number(_major(c.transfersIn))]);
        s.add([const XCell.text('Transferências enviadas'), XCell.number(_major(c.transfersOut))]);
      }
      s.add([const XCell.text('Resultado do mês', XStyle.bold), XCell.number(_major(c.net), XStyle.moneyBold)]);
      s.add([const XCell.text('Saldo final', XStyle.bold), XCell.number(_major(c.closing), XStyle.moneyBold)]);

      void table(String title, List<CategoryTotal> list, Money total, XStyle style) {
        if (list.isEmpty) return;
        s.blank();
        s.add([XCell.text(title, XStyle.header), const XCell.text('Valor', XStyle.header), const XCell.text('%', XStyle.header)]);
        for (final x in list) {
          s.add([
            XCell.text(categoryName(x.categoryId)),
            XCell.number(_major(x.total), style),
            XCell.number(total.minor == 0 ? 0 : x.total.minor / total.minor, XStyle.percent),
          ]);
        }
        s.add([const XCell.text('Total', XStyle.bold), XCell.number(_major(total), XStyle.moneyBold)]);
      }

      table('Entradas por categoria', c.incomeByCategory, c.income, XStyle.moneyIncome);
      table('Saídas por categoria', c.expenseByCategory, c.expense, XStyle.moneyExpense);
    }

    final movements = [...report.movements]..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.createdAt.compareTo(b.createdAt);
      });
    s.blank();
    s.add([
      XCell.text('Movimentos (${movements.length})', XStyle.header),
      const XCell.text('Valor', XStyle.header),
      const XCell.text('Data', XStyle.header),
      const XCell.text('Categoria / destino', XStyle.header),
      const XCell.text('Conta', XStyle.header),
      const XCell.text('Tipo', XStyle.header),
    ]);
    for (final mv in movements) {
      final kind = mv.kind;
      final signed = kind == MovementKind.expense ? -_major(mv.amount) : _major(mv.amount);
      s.add([
        XCell.text(mv.description.isNotEmpty ? mv.description : categoryName(mv.categoryId)),
        XCell.number(
          signed,
          kind == MovementKind.expense
              ? XStyle.moneyExpense
              : kind == MovementKind.income
                  ? XStyle.moneyIncome
                  : XStyle.money,
        ),
        XCell.date(mv.date),
        XCell.text(kind == MovementKind.transfer ? '-> ${accountName(mv.toAccountId)}' : categoryName(mv.categoryId)),
        XCell.text(accountName(mv.accountId)),
        XCell.text(movementKindLabel(kind)),
      ]);
    }
    if (movements.isEmpty) s.add([const XCell.text('Sem movimentos neste mês.', XStyle.muted)]);
    s.blank();
    s.add([const XCell.text('Valores calculados pelo FINTRACK a partir dos movimentos registados. Não é um extrato bancário.', XStyle.muted)]);
    sheets.add(s);
  }
  return XlsxWriter.build(sheets);
}

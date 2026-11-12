import 'dart:convert';

import 'package:fintrack/reports/pdf_report.dart';
import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pdfSafe troca o que a fonte padrão não desenha', () {
    expect(pdfSafe('−2 500,00 Kz'), '-2 500,00 Kz');
    expect(pdfSafe('Conta → Poupança'), 'Conta -> Poupança');
    expect(pdfSafe('Pão € “ok” 😀'), 'Pão € “ok” ?');
  });

  test('gera um PDF A4 válido com movimentos e compromissos', () async {
    const aoa = Currency.aoa;
    final day = DateTime(2026, 11, 3);
    final account = Account(
      id: 'a',
      type: AccountType.bank,
      name: 'Conta à ordem',
      institution: 'BFA',
      openingBalance: const Money(10000000, aoa),
      startDate: DateTime(2026, 11, 1),
    );
    final ledger = Ledger(
      [account],
      [
        for (var i = 0; i < 80; i++)
          Movement(
            id: 'm$i',
            kind: i.isEven ? MovementKind.expense : MovementKind.income,
            accountId: 'a',
            amount: Money(1000 + i, aoa),
            categoryId: i.isEven ? 'exp.alimentacao' : 'inc.salario',
            description: 'Movimento $i — mercado',
            date: day,
            createdAt: DateTime(2026, 11, 3, 10, i % 60),
          ),
      ],
      commitments: [
        Commitment(
          id: 'c',
          accountId: 'a',
          amount: const Money(4500000, aoa),
          categoryId: 'exp.habitacao',
          description: 'Renda',
          dueDate: DateTime(2026, 11, 28),
          createdAt: day,
        ),
      ],
    );
    final report = PeriodReport.build(ledger, from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 30));
    final bytes = await buildReportPdf(
      report: report,
      ownerName: 'Eusébio',
      categoryName: (id) => Category.defaults.firstWhere((c) => c.id == id).name,
      accountName: (_) => 'Conta à ordem',
      generatedAt: DateTime(2026, 11, 30, 18),
    );
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(3000));
  });
}

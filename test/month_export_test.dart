import 'package:archive/archive.dart';
import 'package:fintrack/importing/xlsx_reader.dart';
import 'package:fintrack/reports/month_export.dart';
import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const aoa = Currency.aoa;
  final account = Account(
    id: 'a',
    type: AccountType.bank,
    name: 'Conta à ordem',
    openingBalance: const Money(10000000, aoa),
    startDate: DateTime(2026, 1, 1),
  );
  var n = 0;
  Movement mv(MovementKind kind, int kz, String cat, DateTime d) => Movement(
        id: 'm${n++}',
        kind: kind,
        accountId: 'a',
        amount: Money(kz * 100, aoa),
        categoryId: cat,
        description: 'Movimento $n',
        date: d,
        createdAt: d,
      );
  final ledger = Ledger([account], [
    mv(MovementKind.income, 300000, 'inc.salario', DateTime(2026, 10, 25)),
    mv(MovementKind.expense, 20000, 'exp.alimentacao', DateTime(2026, 10, 30)),
    mv(MovementKind.expense, 5000, 'exp.transporte', DateTime(2026, 11, 3)),
    mv(MovementKind.income, 300000, 'inc.salario', DateTime(2026, 11, 25)),
    mv(MovementKind.expense, 7000, 'exp.alimentacao', DateTime(2026, 11, 26)),
  ]);
  String name(String? id) => Category.defaults.firstWhere((c) => c.id == id).name;

  test('Excel anual: resumo por categoria e mês, uma folha por mês', () {
    const cycle = MonthCycle(25);
    final months = [cycle.byLabel(2026, 11), cycle.byLabel(2026, 12)];
    final bytes = buildMonthsWorkbook(
      ledger: ledger,
      months: months,
      cycle: cycle,
      categoryName: name,
      accountName: (_) => 'Conta à ordem',
      today: DateTime(2026, 11, 30),
    );
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(zip.findFile('xl/worksheets/sheet3.xml'), isNotNull, reason: 'resumo + 2 meses');

    final rows = XlsxReader.read(bytes);
    String cell(String label, int col) => rows.firstWhere((r) => r.first == label)[col];
    expect(rows.first.first, contains('Resumo anual 2026'));
    final header = rows.firstWhere((r) => r.first == 'Categoria');
    expect(header.sublist(1), ['Nov 2026', 'Dez 2026', 'Total']);
    // Novembro (25 out a 24 nov): salário de 25/10, 20 000 + 5 000 de saídas.
    expect(cell('Salário', 1), '300000');
    expect(cell('Salário', 2), '300000');
    expect(cell('Salário', 3), '600000');
    expect(cell('Total saídas', 1), '25000');
    expect(cell('Total saídas', 2), '7000');
    expect(cell('Saldo do mês (entradas - saídas)', 3), '568000');
  });

  test('Excel de um mês: só a folha desse mês', () {
    final bytes = buildMonthsWorkbook(
      ledger: ledger,
      months: [MonthCycle.calendar.byLabel(2026, 11)],
      cycle: MonthCycle.calendar,
      categoryName: name,
      accountName: (_) => 'Conta à ordem',
      today: DateTime(2026, 11, 30),
    );
    final rows = XlsxReader.read(bytes);
    expect(rows.first.first, 'Novembro de 2026');
    expect(rows.any((r) => r.first == 'Saídas por categoria'), isTrue);
    expect(rows.any((r) => r.first.startsWith('Movimentos (3)')), isTrue);
  });
}

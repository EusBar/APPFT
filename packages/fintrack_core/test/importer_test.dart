import 'package:fintrack_core/fintrack_core.dart';
import 'package:test/test.dart';

void main() {
  const aoa = Currency.aoa;
  final today = DateTime(2026, 11, 12);
  final account = Account(
    id: 'a',
    type: AccountType.bank,
    name: 'BAI',
    openingBalance: const Money(0, aoa),
    startDate: DateTime(2026, 1, 1),
  );
  var n = 0;

  List<ImportRow> plan(String csv, {Ledger? ledger, ImportColumns? columns}) {
    final rows = TabularText.parse(csv);
    return ImportPlan.build(
      rows: rows,
      hasHeader: true,
      columns: columns ?? ImportColumns.guess(rows.first),
      account: account,
      categories: Category.defaults,
      ledger: ledger ?? Ledger([account], []),
      today: today,
      batchId: 'lote1',
      newId: () => 'id${n++}',
      now: () => DateTime(2026, 11, 12, 10),
    );
  }

  group('TabularText', () {
    test('ponto e vírgula, aspas, BOM e linhas vazias', () {
      final rows = TabularText.parse('﻿Data;Descrição;Valor\r\n03/11/2026;"Pão; leite";-1.250,50\r\n\r\n');
      expect(rows, [
        ['Data', 'Descrição', 'Valor'],
        ['03/11/2026', 'Pão; leite', '-1.250,50'],
      ]);
    });

    test('vírgula como separador', () {
      expect(TabularText.parse('a,b\n1,"x ""y"""')[1], ['1', 'x "y"']);
    });
  });

  group('datas', () {
    test('formatos comuns', () {
      expect(parseImportDate('2026-11-03'), DateTime(2026, 11, 3));
      expect(parseImportDate('03/11/2026'), DateTime(2026, 11, 3));
      expect(parseImportDate('3-11-26'), DateTime(2026, 11, 3));
      expect(parseImportDate('03.11.2026 14:20'), DateTime(2026, 11, 3));
      expect(parseImportDate('46329'), DateTime(2026, 11, 3), reason: 'série do Excel');
      expect(parseImportDate('31/02/2026'), isNull);
      expect(parseImportDate('ontem'), isNull);
    });
  });

  group('colunas', () {
    test('adivinha cabeçalhos de extrato bancário', () {
      final c = ImportColumns.guess(['Data Mov.', 'Data Valor', 'Descritivo', 'Débito', 'Crédito', 'Saldo']);
      expect(c.date, 0);
      expect(c.amount, isNull);
      expect(c.debit, 3);
      expect(c.credit, 4);
      expect(c.isUsable, isTrue);
    });

    test('lê o próprio CSV do FINTRACK', () {
      final c = ImportColumns.guess(MovementCsv.header);
      expect(c.date, 0);
      expect(c.kind, 1);
      expect(c.description, 2);
      expect(c.category, 3);
      expect(c.amount, 5);
    });
  });

  group('ImportPlan', () {
    test('sinal, débito/crédito, categorias e erros', () {
      final rows = plan('Data;Descrição;Valor;Categoria\n'
          '01/11/2026;Salário;300 000,00;Salário\n'
          '02/11/2026;Mercado;-12.500;Alimentação\n'
          '03/11/2026;Táxi;-2500;Inexistente\n'
          'xx;Erro;10\n'
          '04/11/2026;Zero;0\n'
          '20/11/2026;Futuro;-10\n'
          '05/11/2025;Antes;-10\n');
      expect(rows[0].movement!.kind, MovementKind.income);
      expect(rows[0].movement!.amount, const Money(30000000, aoa));
      expect(rows[0].movement!.categoryId, 'inc.salario');
      expect(rows[0].movement!.origin, MovementOrigin.import);
      expect(rows[0].movement!.batchId, 'lote1');
      expect(rows[1].movement!.kind, MovementKind.expense);
      expect(rows[1].movement!.amount, const Money(1250000, aoa));
      expect(rows[1].movement!.categoryId, 'exp.alimentacao');
      expect(rows[2].movement!.categoryId, 'exp.outros');
      expect(rows[3].issue, ImportIssue.invalidDate);
      expect(rows[4].issue, ImportIssue.zeroAmount);
      expect(rows[5].issue, ImportIssue.inFuture);
      expect(rows[6].issue, ImportIssue.beforeAccountStart);
      expect(rows.where((r) => r.isValid).length, 3);
    });

    test('colunas de débito e crédito', () {
      final rows = plan('Data;Descritivo;Débito;Crédito\n01/11/2026;Renda;45.000,00;\n02/11/2026;Juros;;150,25\n');
      expect(rows[0].movement!.kind, MovementKind.expense);
      expect(rows[0].movement!.amount, const Money(4500000, aoa));
      expect(rows[1].movement!.kind, MovementKind.income);
      expect(rows[1].movement!.amount, const Money(15025, aoa));
    });

    test('duplicados: no ficheiro e no que já existe', () {
      final existing = Movement(
        id: 'e',
        kind: MovementKind.expense,
        accountId: 'a',
        amount: const Money(100000, aoa),
        categoryId: 'exp.alimentacao',
        description: 'Mercado',
        date: DateTime(2026, 11, 2),
        createdAt: DateTime(2026, 11, 2),
      );
      final rows = plan(
        'Data;Descrição;Valor\n02/11/2026;Mercado;-1000\n03/11/2026;Pão;-50\n03/11/2026;Pão;-50\n',
        ledger: Ledger([account], [existing]),
      );
      expect(rows.map((r) => r.duplicate), [true, false, true]);
    });

    test('transferências não se importam', () {
      final rows = plan('Data;Tipo;Valor\n01/11/2026;Transferência;100\n');
      expect(rows.single.issue, ImportIssue.transferNotSupported);
    });
  });

  group('contas e lotes', () {
    test('apagar só sem histórico; arquivar sem pendentes', () {
      final b = Account(
        id: 'b',
        type: AccountType.cash,
        name: 'Carteira',
        openingBalance: const Money(0, aoa),
        startDate: DateTime(2026, 1, 1),
      );
      final m = Movement(
        id: 'm',
        kind: MovementKind.expense,
        accountId: 'b',
        amount: const Money(1, aoa),
        categoryId: 'exp.outros',
        date: today,
        createdAt: today,
      );
      final empty = Ledger([account, b], []);
      expect(empty.canDelete('b'), isTrue);
      expect(empty.canEditOpening('b'), isTrue);
      final used = Ledger([account, b], [m]);
      expect(used.canDelete('b'), isFalse);
      expect(used.canEditOpening('b'), isFalse);
      expect(used.canArchive('b'), isTrue);
      expect(Ledger([account], []).canDelete('a'), isFalse, reason: 'última conta ativa');
    });

    test('lotes de importação em vigor e anulação', () {
      final rows = plan('Data;Descrição;Valor\n01/11/2026;A;-10\n02/11/2026;B;-20\n');
      final moves = [for (final r in rows) r.movement!];
      final l = Ledger([account], moves);
      expect(l.importBatches()['lote1'], hasLength(2));
      final undone = Ledger([account], [
        ...moves,
        for (final m in moves) m.reversal(id: 'r${m.id}', createdAt: today),
      ]);
      expect(undone.importBatches(), isEmpty);
      expect(undone.balanceOf('a'), const Money(0, aoa));
    });
  });
}

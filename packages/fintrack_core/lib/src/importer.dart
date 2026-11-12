import 'account.dart';
import 'category.dart';
import 'ledger.dart';
import 'money.dart';
import 'movement.dart';

/// Leitura de texto tabular (CSV). Deteta o separador (; , ou tabulação),
/// respeita aspas e ignora o BOM do Excel.
class TabularText {
  static List<List<String>> parse(String input) {
    var text = input.startsWith('﻿') ? input.substring(1) : input;
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final firstLine = text.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final delimiter = _guessDelimiter(firstLine);

    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"' && cell.isEmpty) {
        quoted = true;
      } else if (ch == delimiter) {
        row.add(cell.toString().trim());
        cell.clear();
      } else if (ch == '\n') {
        row.add(cell.toString().trim());
        cell.clear();
        if (row.any((c) => c.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    row.add(cell.toString().trim());
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
    return rows;
  }

  static String _guessDelimiter(String line) {
    var best = ';';
    var bestCount = 0;
    for (final d in [';', '\t', ',']) {
      final count = d.allMatches(line).length;
      if (count > bestCount) {
        best = d;
        bestCount = count;
      }
    }
    return best;
  }
}

/// Que coluna (índice) tem cada informação. `null` = não existe no ficheiro.
class ImportColumns {
  const ImportColumns({
    this.date,
    this.description,
    this.amount,
    this.debit,
    this.credit,
    this.kind,
    this.category,
  });

  final int? date;
  final int? description;

  /// Valor com sinal: negativo = saída, positivo = entrada.
  final int? amount;

  /// Alternativa a [amount]: colunas separadas de débito e crédito.
  final int? debit;
  final int? credit;

  /// Coluna "Tipo" (Entrada/Saída), quando existe.
  final int? kind;
  final int? category;

  bool get isUsable => date != null && (amount != null || debit != null || credit != null);

  ImportColumns copyWith({
    int? Function()? date,
    int? Function()? description,
    int? Function()? amount,
    int? Function()? debit,
    int? Function()? credit,
    int? Function()? kind,
    int? Function()? category,
  }) =>
      ImportColumns(
        date: date == null ? this.date : date(),
        description: description == null ? this.description : description(),
        amount: amount == null ? this.amount : amount(),
        debit: debit == null ? this.debit : debit(),
        credit: credit == null ? this.credit : credit(),
        kind: kind == null ? this.kind : kind(),
        category: category == null ? this.category : category(),
      );

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c')
      .trim();

  /// Adivinha as colunas pelos nomes do cabeçalho (português e inglês).
  static ImportColumns guess(List<String> header) {
    int? find(List<String> words, {Set<int> skip = const {}}) {
      for (var i = 0; i < header.length; i++) {
        if (skip.contains(i)) continue;
        final h = _norm(header[i]);
        // "Data valor" é uma data, não um valor.
        if (!words.contains('data') && h.startsWith('data')) continue;
        if (words.any((w) => h == w || h.startsWith('$w ') || h.contains(w))) return i;
      }
      return null;
    }

    final date = find(['data', 'date', 'dia']);
    final debit = find(['debito', 'debit', 'saida', 'levantamento']);
    final credit = find(['credito', 'credit', 'entrada', 'deposito']);
    final amount = find(['valor', 'montante', 'importancia', 'amount', 'quantia'],
        skip: {if (debit != null) debit, if (credit != null) credit});
    return ImportColumns(
      date: date,
      description: find(['descricao', 'descritivo', 'description', 'historico', 'designacao', 'detalhe']),
      amount: amount,
      debit: amount == null ? debit : null,
      credit: amount == null ? credit : null,
      kind: find(['tipo', 'type', 'natureza']),
      category: find(['categoria', 'category']),
    );
  }
}

/// Datas comuns em extratos: 2026-11-03, 03/11/2026, 03-11-2026, 03.11.26,
/// e números de série do Excel (ex.: 46329).
DateTime? parseImportDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);
  if (iso != null) {
    return _valid(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  }
  final dmy = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$').firstMatch(s.split(' ').first);
  if (dmy != null) {
    var y = int.parse(dmy[3]!);
    if (y < 100) y += 2000;
    return _valid(y, int.parse(dmy[2]!), int.parse(dmy[1]!));
  }
  final serial = double.tryParse(s);
  if (serial != null && serial > 20000 && serial < 80000) {
    final d = DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor()));
    return DateTime(d.year, d.month, d.day);
  }
  return null;
}

DateTime? _valid(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final date = DateTime(y, m, d);
  return date.month == m && date.day == d ? date : null;
}

enum ImportIssue {
  missingDate,
  invalidDate,
  missingAmount,
  invalidAmount,
  zeroAmount,
  transferNotSupported,
  beforeAccountStart,
  inFuture,
}

/// Uma linha do ficheiro já interpretada.
class ImportRow {
  const ImportRow({
    required this.line,
    this.movement,
    this.issue,
    this.duplicate = false,
  });

  /// Número da linha no ficheiro (1 = primeira).
  final int line;
  final Movement? movement;
  final ImportIssue? issue;

  /// Já existe no FINTRACK ou aparece repetida no ficheiro.
  final bool duplicate;

  bool get isValid => movement != null && issue == null;
}

/// Prepara movimentos a partir das linhas. Nada é gravado aqui: o
/// utilizador vê a pré-visualização e confirma.
class ImportPlan {
  static List<ImportRow> build({
    required List<List<String>> rows,
    required bool hasHeader,
    required ImportColumns columns,
    required Account account,
    required List<Category> categories,
    required Ledger ledger,
    required DateTime today,
    required String batchId,
    required String Function() newId,
    required DateTime Function() now,
  }) {
    String cell(List<String> r, int? i) => i == null || i >= r.length ? '' : r[i].trim();
    String norm(String s) => ImportColumns._norm(s);

    Category? categoryByName(String name, CategoryKind kind) {
      final n = norm(name);
      if (n.isEmpty) return null;
      for (final c in categories) {
        if (c.kind == kind && !c.archived && norm(c.name) == n) return c;
      }
      return null;
    }

    final fallback = {
      CategoryKind.expense: categories.firstWhere(
        (c) => c.id == 'exp.outros',
        orElse: () => categories.firstWhere((c) => c.kind == CategoryKind.expense),
      ),
      CategoryKind.income: categories.firstWhere(
        (c) => c.id == 'inc.outros',
        orElse: () => categories.firstWhere((c) => c.kind == CategoryKind.income),
      ),
    };

    final result = <ImportRow>[];
    final seen = <String>{};
    for (var i = hasHeader ? 1 : 0; i < rows.length; i++) {
      final r = rows[i];
      final line = i + 1;
      ImportRow fail(ImportIssue issue) => ImportRow(line: line, issue: issue);

      final rawDate = cell(r, columns.date);
      if (rawDate.isEmpty) {
        result.add(fail(ImportIssue.missingDate));
        continue;
      }
      final date = parseImportDate(rawDate);
      if (date == null) {
        result.add(fail(ImportIssue.invalidDate));
        continue;
      }

      // Valor e sentido.
      Money? signed;
      try {
        if (columns.amount != null) {
          final raw = cell(r, columns.amount);
          if (raw.isNotEmpty) signed = Money.parse(raw, account.currency);
        } else {
          final d = cell(r, columns.debit);
          final c = cell(r, columns.credit);
          if (d.isNotEmpty && Money.parse(d, account.currency).minor != 0) {
            signed = -Money(Money.parse(d, account.currency).minor.abs(), account.currency);
          } else if (c.isNotEmpty) {
            signed = Money(Money.parse(c, account.currency).minor.abs(), account.currency);
          }
        }
      } on FormatException {
        result.add(fail(ImportIssue.invalidAmount));
        continue;
      }
      if (signed == null) {
        result.add(fail(ImportIssue.missingAmount));
        continue;
      }
      if (signed.isZero) {
        result.add(fail(ImportIssue.zeroAmount));
        continue;
      }

      var kind = signed.isNegative ? MovementKind.expense : MovementKind.income;
      final kindText = norm(cell(r, columns.kind));
      if (kindText.isNotEmpty) {
        if (kindText.contains('transf')) {
          result.add(fail(ImportIssue.transferNotSupported));
          continue;
        }
        if (RegExp('saida|debito|despesa|expense|pagamento').hasMatch(kindText)) {
          kind = MovementKind.expense;
        } else if (RegExp('entrada|credito|receita|income|recebimento').hasMatch(kindText)) {
          kind = MovementKind.income;
        }
      }

      final categoryKind = kind == MovementKind.income ? CategoryKind.income : CategoryKind.expense;
      final category =
          categoryByName(cell(r, columns.category), categoryKind) ?? fallback[categoryKind]!;
      final description = cell(r, columns.description);

      final movement = Movement(
        id: newId(),
        kind: kind,
        accountId: account.id,
        amount: Money(signed.minor.abs(), account.currency),
        categoryId: category.id,
        description: description.length > Movement.descriptionMaxLength
            ? description.substring(0, Movement.descriptionMaxLength)
            : description,
        date: date,
        origin: MovementOrigin.import,
        batchId: batchId,
        createdAt: now(),
      );

      final issue = ledger.check(movement, today: today);
      if (issue == MovementIssue.beforeAccountStart) {
        result.add(ImportRow(line: line, movement: movement, issue: ImportIssue.beforeAccountStart));
        continue;
      }
      if (issue == MovementIssue.inFuture) {
        result.add(ImportRow(line: line, movement: movement, issue: ImportIssue.inFuture));
        continue;
      }

      final key = '${movement.date}|${movement.kind}|${movement.amount.minor}|${norm(description)}';
      final duplicate = !seen.add(key) || ledger.possibleDuplicate(movement) != null;
      result.add(ImportRow(line: line, movement: movement, duplicate: duplicate));
    }
    return result;
  }
}

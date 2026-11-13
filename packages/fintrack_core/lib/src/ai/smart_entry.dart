import '../account.dart';
import '../category.dart';
import '../currency.dart';
import '../money.dart';
import '../movement.dart';
import '../planning.dart';

/// Campos que o utilizador tem de completar antes de gravar.
enum EntryField { kind, amount, account, category }

/// Movimento preparado a partir de texto ou SMS. Nunca é gravado sozinho:
/// o utilizador revê, completa e confirma.
class EntryDraft {
  const EntryDraft({
    this.kind,
    this.amount,
    this.accountId,
    this.categoryId,
    required this.date,
    this.dateAssumed = false,
    this.description = '',
    this.missing = const {},
    this.notes = const [],
  });

  final MovementKind? kind;
  final Money? amount;
  final String? accountId;
  final String? categoryId;
  final DateTime date;

  /// Sem data no texto: ficou "hoje".
  final bool dateAssumed;
  final String description;
  final Set<EntryField> missing;

  /// Explicações curtas do que foi interpretado ou ficou por decidir.
  final List<String> notes;

  bool get complete => missing.isEmpty;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâã]'), 'a')
    .replaceAll(RegExp('[éê]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll(RegExp('[óôõ]'), 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c');

/// Smart Entry local (secção 13): interpreta frases como "Despesa de 12 500 Kz
/// em alimentação, hoje, conta principal" ou o SMS colado do banco.
/// Corre no telemóvel, sem Internet. Na dúvida, pergunta: nunca adivinha
/// conta nem moeda.
class SmartEntryParser {
  static final _expenseWords = RegExp(
      r'\b(despesa|gastei|gasto|paguei|pagamento|pagar|compra|comprei|saida|debito|debitado|levantamento|levantei)\b');
  static final _incomeWords = RegExp(
      r'\b(recebi|recebimento|receita|entrada|ganhei|salario|credito|creditado|deposito|depositei|reembolso)\b');
  static final _transferWords = RegExp(r'\b(transferi|transferencia|transferir|passei para)\b');

  static const _currencyWords = {
    'kz': Currency.aoa,
    'kwanza': Currency.aoa,
    'kwanzas': Currency.aoa,
    'aoa': Currency.aoa,
    'usd': Currency.usd,
    'dolar': Currency.usd,
    'dolares': Currency.usd,
    'us\$': Currency.usd,
    '\$': Currency.usd,
    'eur': Currency.eur,
    'euro': Currency.eur,
    'euros': Currency.eur,
    '€': Currency.eur,
    'brl': Currency.brl,
    'r\$': Currency.brl,
    'reais': Currency.brl,
    'gbp': Currency.gbp,
    '£': Currency.gbp,
    'zar': Currency.zar,
    'rand': Currency.zar,
  };

  /// Palavras do dia a dia que apontam para uma categoria inicial.
  static const _hints = {
    'exp.alimentacao': ['mercado', 'supermercado', 'kero', 'shoprite', 'candando', 'comida', 'almoco', 'jantar', 'restaurante', 'pao', 'padaria', 'alimentacao'],
    'exp.transporte': ['taxi', 'candongueiro', 'combustivel', 'gasolina', 'gasoleo', 'uber', 'heetch', 'yango', 'transporte', 'autocarro'],
    'exp.habitacao': ['renda', 'aluguer', 'casa', 'agua', 'luz', 'ende', 'epal', 'condominio', 'habitacao'],
    'exp.saude': ['farmacia', 'medico', 'clinica', 'hospital', 'consulta', 'saude', 'medicamento'],
    'exp.educacao': ['propina', 'propinas', 'escola', 'colegio', 'universidade', 'curso', 'livros', 'educacao'],
    'exp.domesticas': ['internet', 'unitel', 'movicel', 'africell', 'tv', 'dstv', 'zap', 'gas', 'domesticas'],
    'exp.kixikila': ['kixikila'],
    'inc.salario': ['salario', 'ordenado', 'vencimento'],
    'inc.kixikila': ['kixikila'],
  };

  static EntryDraft parse(
    String text, {
    required List<Account> accounts,
    required List<Category> categories,
    required DateTime today,
    CategorySuggester? suggester,
  }) {
    final n = _norm(text);
    final notes = <String>[];
    final missing = <EntryField>{};

    // Tipo.
    MovementKind? kind;
    if (_transferWords.hasMatch(n)) {
      notes.add('Transferências entre contas registam-se no formulário.');
      kind = MovementKind.transfer;
    } else if (_expenseWords.hasMatch(n) && !_incomeWords.hasMatch(n)) {
      kind = MovementKind.expense;
    } else if (_incomeWords.hasMatch(n) && !_expenseWords.hasMatch(n)) {
      kind = MovementKind.income;
    } else if (_expenseWords.hasMatch(n) && _incomeWords.hasMatch(n)) {
      // Ex.: SMS "Débito ... saldo disponível": vence a primeira palavra.
      kind = _expenseWords.firstMatch(n)!.start < _incomeWords.firstMatch(n)!.start
          ? MovementKind.expense
          : MovementKind.income;
    }
    if (kind == null) missing.add(EntryField.kind);

    // Conta: pelo nome, instituição ou tipo; com uma só conta, é essa.
    final open = [for (final a in accounts) if (!a.archived) a];
    Account? account;
    for (final a in open) {
      final names = [_norm(a.name), if (a.institution != null) _norm(a.institution!)];
      if (names.any((x) => x.length >= 3 && n.contains(x))) {
        account = a;
        break;
      }
    }
    if (account == null && RegExp(r'\b(numerario|dinheiro|carteira|cash)\b').hasMatch(n)) {
      account = open.where((a) => a.type == AccountType.cash).firstOrNull;
    }
    if (account == null && RegExp(r'conta principal').hasMatch(n) && open.isNotEmpty) {
      account = open.first;
    }
    if (account == null && open.length == 1) account = open.single;
    if (account == null) missing.add(EntryField.account);

    // Moeda e valor.
    Currency? currency;
    for (final e in _currencyWords.entries) {
      final word = RegExp('(^|[^a-z])${RegExp.escape(e.key)}(\$|[^a-z])');
      if (word.hasMatch(n)) {
        currency = e.value;
        break;
      }
    }
    currency ??= account?.currency;
    Money? amount;
    final amountMatch = RegExp(r'(\d[\d .,]*\d|\d)\s*(mil|k)?\b').allMatches(n).where((m) {
      // Ignora datas (03/11/2026) e números de conta mascarados.
      final before = m.start > 0 ? n[m.start - 1] : ' ';
      final after = m.end < n.length ? n[m.end] : ' ';
      return before != '/' && after != '/' && before != '*';
    }).toList();
    if (amountMatch.isNotEmpty && currency != null) {
      // O maior número escrito é o valor (evita apanhar "dia 5").
      Money? best;
      for (final m in amountMatch) {
        var raw = m.group(1)!.trim();
        var multiplier = 1;
        if (m.group(2) != null) multiplier = 1000;
        try {
          var money = Money.parse(raw, currency);
          money = Money(money.minor * multiplier, currency);
          if (best == null || money.minor.abs() > best.minor.abs()) best = money;
        } on FormatException {
          raw = '';
        }
      }
      if (best != null && best.minor > 0) amount = best;
    }
    if (amount == null) missing.add(EntryField.amount);
    if (account != null && currency != null && currency != account.currency) {
      notes.add('A moeda (${currency.code}) é diferente da conta (${account.currency.code}).');
      missing.add(EntryField.account);
    }

    // Data.
    var date = DateTime(today.year, today.month, today.day);
    var assumed = false;
    final dm = RegExp(r'\b(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?\b').firstMatch(n);
    if (n.contains('anteontem')) {
      date = date.subtract(const Duration(days: 2));
    } else if (n.contains('ontem')) {
      date = date.subtract(const Duration(days: 1));
    } else if (dm != null) {
      var y = dm.group(3) == null ? today.year : int.parse(dm.group(3)!);
      if (y < 100) y += 2000;
      final candidate = DateTime(y, int.parse(dm.group(2)!), int.parse(dm.group(1)!));
      if (candidate.month == int.parse(dm.group(2)!)) date = candidate;
    } else if (RegExp(r'\bdia (\d{1,2})\b').firstMatch(n) case final d?) {
      final day = int.parse(d.group(1)!);
      final candidate = DateTime(today.year, today.month, day);
      date = candidate.isAfter(today) ? DateTime(today.year, today.month - 1, day) : candidate;
    } else if (!n.contains('hoje')) {
      assumed = true;
    }

    // Categoria: palavras do texto, nome da categoria, depois histórico.
    String? categoryId;
    if (kind == MovementKind.expense || kind == MovementKind.income) {
      final wanted = kind == MovementKind.income ? CategoryKind.income : CategoryKind.expense;
      final valid = {for (final c in categories) if (c.kind == wanted && !c.archived) c.id: c};
      for (final c in valid.values) {
        if (n.contains(_norm(c.name))) {
          categoryId = c.id;
          break;
        }
      }
      if (categoryId == null) {
        for (final e in _hints.entries) {
          if (!valid.containsKey(e.key)) continue;
          if (e.value.any((w) => RegExp('\\b$w\\b').hasMatch(n))) {
            categoryId = e.key;
            break;
          }
        }
      }
      categoryId ??= suggester?.suggest(text, kind!, categories);
      if (categoryId == null) missing.add(EntryField.category);
    }

    // Descrição: o texto sem números, moedas e palavras de ligação.
    var description = text
        .replaceAll(RegExp(r'\d[\d .,/]*\d|\d'), ' ')
        .replaceAll(RegExp(r'\b(kz|aoa|usd|eur|kwanzas?|mil|hoje|ontem|anteontem|de|do|da|no|na|em|com|para|conta principal)\b',
            caseSensitive: false), ' ')
        .replaceAll(RegExp(r'[,;:]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (description.length > 60) description = description.substring(0, 60).trim();
    if (description.isNotEmpty) {
      description = description[0].toUpperCase() + description.substring(1);
    }

    return EntryDraft(
      kind: kind,
      amount: amount,
      accountId: account?.id,
      categoryId: categoryId,
      date: date,
      dateAssumed: assumed,
      description: description,
      missing: missing,
      notes: notes,
    );
  }
}

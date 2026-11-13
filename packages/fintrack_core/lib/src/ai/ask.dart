import '../category.dart';
import '../commitment.dart';
import '../currency.dart';
import '../ledger.dart';
import '../money.dart';
import '../movement.dart';
import '../planning.dart';
import 'insights.dart';

/// Resposta a uma pergunta: um texto curto e, opcionalmente, linhas de
/// detalhe. Todos os valores vêm do livro-razão.
class AskAnswer {
  const AskAnswer(this.text, {this.lines = const [], this.understood = true});

  final String text;
  final List<String> lines;

  /// `false` quando a pergunta não foi percebida (mostra exemplos).
  final bool understood;
}

/// Período reconhecido numa pergunta.
class AskPeriod {
  const AskPeriod(this.from, this.to, this.label);
  final DateTime from;
  final DateTime to;
  final String label;
}

/// Perguntas em português, respondidas no telemóvel, sem Internet.
///
/// Reconhece a intenção por palavras-chave, o período ("este mês", "mês
/// passado", "outubro", "esta semana", "hoje", "este ano") e a categoria pelo
/// nome. Nada é inventado: sem dados, diz que não há.
class AskEngine {
  AskEngine({
    required this.ledger,
    required this.categories,
    required this.currency,
    required this.today,
    this.budgets = const [],
    this.goals = const [],
    this.contributions = const [],
    this.horizon = AvailableHorizon.endOfMonth,
  });

  final Ledger ledger;
  final List<Category> categories;
  final Currency currency;
  final DateTime today;
  final List<Budget> budgets;
  final List<Goal> goals;
  final List<GoalContribution> contributions;
  final AvailableHorizon horizon;

  static const examples = [
    'Quanto gastei este mês?',
    'Quanto gastei em alimentação no mês passado?',
    'Em que gasto mais?',
    'Quanto posso gastar?',
    'Que contas tenho para pagar?',
    'Compara com o mês passado',
    'Como vão os meus objetivos?',
    'Quanto recebi este ano?',
  ];

  static const _months = [
    'janeiro', 'fevereiro', 'marco', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
  ];

  /// Minúsculas e sem acentos, para comparar palavras.
  static String normalize(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  DateTime get _t => DateTime(today.year, today.month, today.day);
  String _fmt(Money m) => m.format();

  AskPeriod period(String q) {
    final t = _t;
    if (q.contains('mes passado') || q.contains('ultimo mes') || q.contains('mes anterior')) {
      final s = DateTime(t.year, t.month - 1, 1);
      return AskPeriod(s, DateTime(s.year, s.month + 1, 0), 'no mês passado');
    }
    for (var i = 0; i < 12; i++) {
      if (RegExp('\\b${_months[i]}\\b').hasMatch(q)) {
        var year = t.year;
        if (i + 1 > t.month) year -= 1; // um mês ainda por vir é do ano passado
        final s = DateTime(year, i + 1, 1);
        final e = DateTime(year, i + 2, 0);
        final label = 'em ${_months[i] == 'marco' ? 'março' : _months[i]}${year != t.year ? ' de $year' : ''}';
        return AskPeriod(s, e.isAfter(t) ? t : e, label);
      }
    }
    if (q.contains('hoje')) return AskPeriod(t, t, 'hoje');
    if (q.contains('ontem')) {
      final y = t.subtract(const Duration(days: 1));
      return AskPeriod(y, y, 'ontem');
    }
    if (q.contains('semana')) {
      final s = t.subtract(Duration(days: t.weekday - 1));
      return AskPeriod(s, t, 'esta semana');
    }
    if (RegExp(r'\bano\b').hasMatch(q)) {
      return AskPeriod(DateTime(t.year, 1, 1), t, 'este ano');
    }
    return AskPeriod(DateTime(t.year, t.month, 1), t, 'este mês');
  }

  /// Categoria mencionada (pelo nome, ou pelo início das palavras).
  Category? category(String q, CategoryKind kind) {
    Category? best;
    var bestLen = 0;
    for (final c in categories) {
      if (c.kind != kind || c.archived) continue;
      final name = normalize(c.name);
      final words = name.split(' ').where((w) => w.length >= 4);
      // "alimentacao" ~ "alimentos", "transportes" ~ "transporte".
      final qWords = q.split(' ').where((x) => x.length >= 5);
      final hit = q.contains(name) ||
          words.any((w) => qWords.any((x) => x.substring(0, 5) == w.padRight(5).substring(0, 5)));
      if (hit && name.length > bestLen) {
        best = c;
        bestLen = name.length;
      }
    }
    return best;
  }

  String _name(String id) {
    for (final c in categories) {
      if (c.id == id) return c.name;
    }
    return 'Outros';
  }

  bool _any(String q, List<String> words) => words.any(q.contains);

  AskAnswer ask(String question) {
    final q = normalize(question);
    if (q.isEmpty) return const AskAnswer('Escreva uma pergunta.', understood: false);

    if (_any(q, ['compar', 'diferenca', 'evolu'])) return _compare();
    if (_any(q, ['posso gastar', 'disponivel', 'sobra', 'resta'])) return _available();
    if (_any(q, ['pagar', 'compromisso', 'contas a', 'vencer', 'dividas'])) return _commitments();
    if (_any(q, ['objetivo', 'meta', 'poupanca', 'juntar'])) return _goals();
    if (_any(q, ['orcamento', 'limite'])) return _budgets();
    if (_any(q, ['mais gasto', 'gasto mais', 'gastei mais', 'maior gasto', 'maiores gastos', 'onde gasto', 'em que gasto', 'categoria'])) {
      return _top(period(q));
    }
    if (_any(q, ['recebi', 'ganhei', 'entrada', 'rendimento', 'salario', 'receb'])) {
      return _total(q, MovementKind.income);
    }
    if (_any(q, ['gast', 'despes', 'saida', 'paguei', 'compr', 'consum'])) {
      return _total(q, MovementKind.expense);
    }
    if (_any(q, ['saldo', 'tenho', 'quanto ha', 'dinheiro'])) return _balance();
    if (_any(q, ['tendenc', 'resumo', 'analise', 'como estou', 'como vao', 'como esta'])) return _summary();
    return const AskAnswer(
      'Ainda não sei responder a isso. Experimente uma destas perguntas:',
      lines: examples,
      understood: false,
    );
  }

  AskAnswer _total(String q, MovementKind kind) {
    final p = period(q);
    final cat = category(q, kind == MovementKind.expense ? CategoryKind.expense : CategoryKind.income);
    final total = TrendsEngine.total(ledger, kind, currency, from: p.from, to: p.to, categoryId: cat?.id);
    final verb = kind == MovementKind.expense ? 'Gastou' : 'Recebeu';
    final where = cat == null ? '' : ' em ${cat.name}';
    if (total.isZero) {
      return AskAnswer('Não há ${kind == MovementKind.expense ? 'saídas' : 'entradas'}$where registadas ${p.label}.');
    }
    final lines = <String>[];
    if (cat == null) {
      final list = TrendsEngine.byCategory(ledger, currency, from: p.from, to: p.to, kind: kind);
      for (final (id, v) in list.take(5)) {
        lines.add('${_name(id)}: ${_fmt(v)}');
      }
    }
    return AskAnswer('$verb ${_fmt(total)}$where ${p.label}.', lines: lines);
  }

  AskAnswer _top(AskPeriod p) {
    final list = TrendsEngine.byCategory(ledger, currency, from: p.from, to: p.to);
    if (list.isEmpty) return AskAnswer('Não há saídas registadas ${p.label}.');
    final total = list.fold<int>(0, (s, e) => s + e.$2.minor);
    final (id, top) = list.first;
    final share = (top.minor * 100 / total).round();
    return AskAnswer(
      '${p.label[0].toUpperCase()}${p.label.substring(1)}, gasta mais em ${_name(id)}: ${_fmt(top)} ($share% das saídas).',
      lines: [for (final (cid, v) in list.take(5)) '${_name(cid)}: ${_fmt(v)}'],
    );
  }

  AskAnswer _compare() {
    final t = _t;
    final s = DateTime(t.year, t.month, 1);
    final ps = DateTime(t.year, t.month - 1, 1);
    final pe = DateTime(ps.year, ps.month + 1, 0);
    final same = DateTime(ps.year, ps.month, t.day > pe.day ? pe.day : t.day);
    final now = TrendsEngine.total(ledger, MovementKind.expense, currency, from: s, to: t);
    final before = TrendsEngine.total(ledger, MovementKind.expense, currency, from: ps, to: same);
    if (before.isZero) {
      return AskAnswer('Este mês gastou ${_fmt(now)}. Não há saídas no mesmo período do mês passado para comparar.');
    }
    final change = ((now.minor - before.minor) * 100 / before.minor).round();
    final how = change == 0 ? 'o mesmo que' : change > 0 ? '$change% mais do que' : '${-change}% menos do que';
    final lines = <String>[];
    final cur = {for (final (id, v) in TrendsEngine.byCategory(ledger, currency, from: s, to: t)) id: v.minor};
    final prev = {for (final (id, v) in TrendsEngine.byCategory(ledger, currency, from: ps, to: same)) id: v.minor};
    final diffs = [
      for (final id in {...cur.keys, ...prev.keys}) (id, (cur[id] ?? 0) - (prev[id] ?? 0)),
    ]..sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));
    for (final (id, d) in diffs.take(4)) {
      if (d == 0) continue;
      lines.add('${_name(id)}: ${d > 0 ? 'mais' : 'menos'} ${_fmt(Money(d.abs(), currency))}');
    }
    return AskAnswer(
      'Até dia ${t.day}, gastou ${_fmt(now)}: $how no mesmo período do mês passado (${_fmt(before)}).',
      lines: lines,
    );
  }

  AskAnswer _available() {
    final av = ledger.available(today: _t, horizon: horizon)[currency];
    final committed = ledger.committed(today: _t, horizon: horizon)[currency];
    if (av == null) return const AskAnswer('Não há contas nesta moeda para calcular o disponível.');
    return AskAnswer(
      av.minor >= 0
          ? 'Pode gastar ${_fmt(av)} sem tocar no dinheiro dos compromissos.'
          : 'Atenção: faltam ${_fmt(-av)} para cobrir os compromissos pendentes.',
      lines: [
        if (committed != null && !committed.isZero) 'Já reservado para compromissos: ${_fmt(committed)}',
      ],
    );
  }

  AskAnswer _balance() {
    final lines = <String>[];
    for (final a in ledger.accounts.values) {
      if (a.archived) continue;
      lines.add('${a.name}: ${_fmt(ledger.balanceOf(a.id))}');
    }
    final totals = ledger.balances();
    if (totals.isEmpty) return const AskAnswer('Ainda não tem contas.');
    final text = totals.values.map(_fmt).join(' · ');
    return AskAnswer('Saldo total: $text.', lines: lines);
  }

  AskAnswer _commitments() {
    final t = _t;
    final pending = ledger.pending();
    if (pending.isEmpty) return const AskAnswer('Não tem compromissos por pagar.');
    final end = DateTime(t.year, t.month + 1, 0);
    final soon = [for (final c in pending) if (!c.dueDate.isAfter(end)) c];
    final late = [for (final c in pending) if (c.dueDate.isBefore(t)) c];
    final sum = soon.where((c) => c.amount.currency == currency).fold<int>(0, (s, c) => s + c.amount.minor);
    String d(DateTime x) => '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}';
    return AskAnswer(
      soon.isEmpty
          ? 'Nada a pagar até ao fim do mês. O próximo é ${pending.first.description}, a ${d(pending.first.dueDate)}.'
          : 'Até ao fim do mês tem ${soon.length} ${soon.length == 1 ? 'compromisso' : 'compromissos'}: ${_fmt(Money(sum, currency))}.'
              '${late.isNotEmpty ? ' ${late.length} em atraso.' : ''}',
      lines: [for (final c in (soon.isEmpty ? pending : soon).take(6)) '${d(c.dueDate)} · ${c.description}: ${_fmt(c.amount)}'],
    );
  }

  AskAnswer _goals() {
    final active = [for (final g in goals) if (!g.archived) g];
    if (active.isEmpty) return const AskAnswer('Ainda não tem objetivos. Crie um em Planear → Objetivos.');
    final lines = <String>[];
    for (final g in active) {
      final p = GoalEngine.progress(ledger, g, contributions, today: _t);
      lines.add('${g.name}: ${p.percent}% (${_fmt(p.saved)} de ${_fmt(g.target)})'
          '${p.monthlyNeeded != null ? ' · juntar ${_fmt(p.monthlyNeeded!)}/mês' : ''}');
    }
    final done = active.where((g) => GoalEngine.progress(ledger, g, contributions, today: _t).done).length;
    return AskAnswer(
      done == active.length
          ? 'Parabéns: todos os objetivos estão cumpridos.'
          : 'Tem ${active.length} ${active.length == 1 ? 'objetivo' : 'objetivos'}${done > 0 ? ', $done já cumprido${done > 1 ? 's' : ''}' : ''}.',
      lines: lines,
    );
  }

  AskAnswer _budgets() {
    if (budgets.isEmpty) return const AskAnswer('Ainda não tem orçamentos. Crie um em Planear → Orçamentos.');
    final lines = <String>[];
    var over = 0;
    for (final b in budgets) {
      final s = BudgetEngine.status(ledger, b, month: _t, today: _t);
      if (s.percent >= 100) over++;
      final name = b.categoryId == null ? 'Global' : _name(b.categoryId!);
      lines.add('$name: ${s.percent}% (${_fmt(s.spent)} de ${_fmt(s.limit)})');
    }
    return AskAnswer(
      over == 0 ? 'Todos os orçamentos estão dentro do limite.' : '$over ${over == 1 ? 'orçamento passou' : 'orçamentos passaram'} o limite.',
      lines: lines,
    );
  }

  AskAnswer _summary() {
    final insights = TrendsEngine.insights(ledger, currency, today: _t, categoryName: _name);
    if (insights.isEmpty) return const AskAnswer('Ainda não há movimentos suficientes para uma análise. Continue a registar.');
    return AskAnswer(insights.first.title, lines: [for (final i in insights) '${i.title}. ${i.detail}']);
  }
}

import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../security/session.dart';

/// "Pergunte ao FINTRACK": perguntas em português respondidas no telemóvel,
/// sem Internet. Os valores vêm diretamente do livro-razão.
class AskCard extends ConsumerStatefulWidget {
  const AskCard({super.key, required this.data, required this.currency, required this.discreet});

  final FinanceData data;
  final Currency currency;
  final bool discreet;

  @override
  ConsumerState<AskCard> createState() => _AskCardState();
}

class _AskCardState extends ConsumerState<AskCard> {
  static const _chips = [
    'Quanto gastei este mês?',
    'Em que gasto mais?',
    'Quanto posso gastar?',
    'Compara com o mês passado',
    'Que contas tenho para pagar?',
    'Como vão os meus objetivos?',
  ];

  final _question = TextEditingController();
  String? _asked;
  AskAnswer? _answer;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  void _ask([String? preset]) {
    final q = (preset ?? _question.text).trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    final data = widget.data;
    final engine = AskEngine(
      ledger: data.ledger,
      categories: data.categories,
      currency: widget.currency,
      today: DateTime.now(),
      budgets: data.budgets,
      goals: data.goals,
      contributions: data.contributions,
      horizon: ref.read(sessionProvider).horizon,
    );
    setState(() {
      _asked = q;
      _answer = engine.ask(q);
      _question.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final answer = _answer;

    return _Panel(
      accent: colors.aiAccent,
      children: [
        Row(children: [
          Icon(Icons.forum_outlined, color: colors.aiAccent),
          const SizedBox(width: FtSpace.sm),
          Expanded(child: Text('Pergunte ao FINTRACK', style: theme.textTheme.titleMedium)),
        ]),
        const SizedBox(height: FtSpace.xs),
        Text('Respostas na hora, calculadas no telemóvel com os seus movimentos.', style: muted),
        const SizedBox(height: FtSpace.sm),
        TextField(
          key: const Key('ask-question'),
          controller: _question,
          maxLength: 200,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _ask(),
          decoration: InputDecoration(
            hintText: 'Ex.: Quanto gastei em transporte em outubro?',
            border: const OutlineInputBorder(),
            counterText: '',
            suffixIcon: IconButton(
              key: const Key('ask-send'),
              tooltip: 'Perguntar',
              icon: const Icon(Icons.send),
              onPressed: _ask,
            ),
          ),
        ),
        const SizedBox(height: FtSpace.sm),
        Wrap(
          spacing: FtSpace.sm,
          runSpacing: FtSpace.xs,
          children: [for (final c in _chips) ActionChip(label: Text(c), onPressed: () => _ask(c))],
        ),
        if (answer != null) ...[
          const SizedBox(height: FtSpace.md),
          Text(_asked!, style: muted?.copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: FtSpace.xs),
          Container(
            key: const Key('ask-answer'),
            padding: const EdgeInsets.all(FtSpace.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(FtRadius.md),
            ),
            child: widget.discreet && answer.understood
                ? const Text('Valores ocultos no modo discreto.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(answer.text, style: theme.textTheme.bodyLarge),
                      for (final l in answer.lines)
                        Padding(
                          padding: const EdgeInsets.only(top: FtSpace.xs),
                          child: answer.understood
                              ? Text('•  $l', style: theme.textTheme.bodyMedium)
                              : InkWell(
                                  onTap: () => _ask(l),
                                  child: Text('•  $l', style: TextStyle(color: theme.colorScheme.primary)),
                                ),
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

/// Tendências: gráfico de 6 meses e observações do mês.
class TrendsCard extends StatelessWidget {
  const TrendsCard({super.key, required this.data, required this.currency, required this.discreet});

  final FinanceData data;
  final Currency currency;
  final bool discreet;

  static const _abbr = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final today = DateTime.now();
    final months = TrendsEngine.months(data.ledger, currency, today: today);
    final insights = TrendsEngine.insights(
      data.ledger,
      currency,
      today: today,
      categoryName: (id) => data.category(id)?.name ?? 'Outros',
    );
    final max = months.fold<int>(1, (m, f) => [m, f.income.minor, f.expense.minor].reduce((a, b) => a > b ? a : b));
    final empty = months.every((m) => m.income.isZero && m.expense.isZero);

    return _Panel(
      accent: colors.aiAccent,
      children: [
        Row(children: [
          Icon(Icons.insights_outlined, color: colors.aiAccent),
          const SizedBox(width: FtSpace.sm),
          Expanded(child: Text('Tendências', style: theme.textTheme.titleMedium)),
          Text(currency.code, style: muted),
        ]),
        const SizedBox(height: FtSpace.md),
        if (empty)
          Text('Registe movimentos para ver aqui a evolução dos últimos 6 meses.', style: muted)
        else ...[
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final m in months)
                  Expanded(
                    child: Semantics(
                      label: discreet
                          ? _abbr[m.month.month - 1]
                          : '${_abbr[m.month.month - 1]}: entradas ${m.income.format()}, saídas ${m.expense.format()}',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _Bar(value: m.income.minor / max, color: colors.income),
                          const SizedBox(width: 3),
                          _Bar(value: m.expense.minor / max, color: colors.expense),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: FtSpace.xs),
          Row(children: [
            for (final m in months)
              Expanded(child: Text(_abbr[m.month.month - 1], textAlign: TextAlign.center, style: muted)),
          ]),
          const SizedBox(height: FtSpace.sm),
          Row(children: [
            _Legend(color: colors.income, label: 'Entradas'),
            const SizedBox(width: FtSpace.md),
            _Legend(color: colors.expense, label: 'Saídas'),
          ]),
        ],
        if (insights.isNotEmpty) ...[
          const SizedBox(height: FtSpace.md),
          for (final i in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: FtSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (i.tone) {
                      InsightTone.good => Icons.check_circle_outline,
                      InsightTone.warning => Icons.warning_amber_rounded,
                      InsightTone.info => Icons.lightbulb_outline,
                    },
                    size: 20,
                    color: switch (i.tone) {
                      InsightTone.good => colors.income,
                      InsightTone.warning => colors.alert,
                      InsightTone.info => colors.aiAccent,
                    },
                  ),
                  const SizedBox(width: FtSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(discreet ? _hideNumbers(i.title) : i.title, style: theme.textTheme.bodyLarge),
                        Text(discreet ? _hideNumbers(i.detail) : i.detail, style: muted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  static String _hideNumbers(String s) => s.replaceAll(RegExp(r'\d[\d\s  .,]*\d|\d'), '•••');
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: (value.clamp(0.0, 1.0) * 110).clamp(2.0, 110.0),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: FtSpace.xs),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children, required this.accent});

  final List<Widget> children;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(FtRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FtSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }
}

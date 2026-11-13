import 'dart:async';
import 'dart:math' as math;

import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../finance/finance_data.dart';

/// Entrada suave (desvanece e sobe), com atraso para criar cascata.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.delay = 0});

  final Widget child;

  /// Atraso em milissegundos.
  final int delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final total = 520 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
      ),
    );
  }
}

/// Superfície de vidro escuro com brilho de cor, usada em todo o separador.
class GlowPanel extends StatelessWidget {
  const GlowPanel({super.key, required this.child, required this.glow, this.padding = FtSpace.md, this.strong = false});

  final Widget child;
  final Color glow;
  final double padding;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(glow.withValues(alpha: strong ? 0.22 : 0.10), scheme.surfaceContainerHigh.withValues(alpha: 0.82)),
            scheme.surfaceContainerHigh.withValues(alpha: 0.70),
          ],
        ),
        border: Border.all(color: glow.withValues(alpha: strong ? 0.45 : 0.22)),
        boxShadow: [BoxShadow(color: glow.withValues(alpha: strong ? 0.18 : 0.08), blurRadius: 32, spreadRadius: -6)],
      ),
      padding: EdgeInsets.all(padding),
      child: child,
    );
  }
}

/// Número que conta até ao valor (unidades mínimas), formatado como dinheiro.
class CountUpMoney extends StatelessWidget {
  const CountUpMoney({super.key, required this.money, this.style, this.discreet = false});

  final Money money;
  final TextStyle? style;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    if (discreet) return Text('•••••• ${money.currency.symbol}', style: style);
    return TweenAnimationBuilder<double>(
      key: ValueKey(money),
      tween: Tween(begin: 0, end: money.minor.toDouble()),
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 900),
      curve: Curves.easeOutExpo,
      builder: (context, v, _) => Text(
        Money(v.round(), money.currency).format(),
        style: style?.copyWith(fontFeatures: ftAmountFeatures),
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
      ),
    );
  }
}

// --- Pulso financeiro --------------------------------------------------------

/// Herói do separador: anel animado com a nota do pulso financeiro.
class PulseHero extends StatelessWidget {
  const PulseHero({super.key, required this.pulse, required this.headline, required this.discreet});

  final FinancialPulse? pulse;
  final Insight? headline;
  final bool discreet;

  Color _tone(FtColors c, int score) => score >= 80
      ? c.income
      : score >= 60
          ? c.aiAccent
          : score >= 40
              ? c.commitment
              : c.expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final p = pulse;
    final tone = p == null ? colors.aiAccent : _tone(colors, p.score);

    return GlowPanel(
      glow: tone,
      strong: true,
      padding: FtSpace.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _PulseRing(score: p?.score ?? 0, color: tone, track: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
              const SizedBox(width: FtSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PULSO FINANCEIRO', style: muted?.copyWith(letterSpacing: 1.6, fontWeight: FontWeight.w600)),
                    const SizedBox(height: FtSpace.xs),
                    Text(
                      p?.label ?? 'A aprender consigo',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: tone),
                    ),
                    const SizedBox(height: FtSpace.xs),
                    Text(
                      p == null
                          ? 'Registe alguns movimentos e o FINTRACK passa a avaliar o seu mês.'
                          : headline == null
                              ? 'Tudo tranquilo por agora.'
                              : discreet
                                  ? 'Toque no olho para ver os detalhes.'
                                  : headline!.title,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (p != null && p.factors.isNotEmpty) ...[
            const SizedBox(height: FtSpace.md),
            Wrap(
              spacing: FtSpace.sm,
              runSpacing: FtSpace.sm,
              children: [
                for (final f in p.factors)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (f.ok ? colors.income : colors.alert).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(f.ok ? Icons.check_rounded : Icons.priority_high_rounded,
                          size: 14, color: f.ok ? colors.income : colors.alert),
                      const SizedBox(width: 4),
                      Text(discreet ? _hide(f.label) : f.label, style: theme.textTheme.labelMedium),
                    ]),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _hide(String s) => s.replaceAll(RegExp(r'\d[\d\s  .,]*\d|\d'), '••');

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.score, required this.color, required this.track});

  final int score;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score / 100),
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: 104,
        height: 104,
        child: CustomPaint(
          painter: _RingPainter(value: v, color: color, track: track),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                '${(v * 100).round()}',
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1),
              ),
              Text('de 100', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track});

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    canvas.drawArc(arc, 0, math.pi * 2, false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    if (value <= 0) return;
    final sweep = math.pi * 2 * value;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [color.withValues(alpha: 0.35), color, color],
        stops: const [0, 0.6, 1],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    // Brilho por baixo do arco.
    canvas.drawArc(arc, -math.pi / 2, sweep, false,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke + 6
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawArc(arc, -math.pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}

// --- Pergunte ao FINTRACK --------------------------------------------------------

class AskPanel extends StatefulWidget {
  const AskPanel({super.key, required this.engine, required this.discreet});

  /// Cria o motor na hora da pergunta (dados sempre atuais).
  final AskEngine Function() engine;
  final bool discreet;

  @override
  State<AskPanel> createState() => _AskPanelState();
}

class _AskPanelState extends State<AskPanel> {
  static const _chips = [
    ('Quanto gastei este mês?', Icons.receipt_long_outlined),
    ('Em que gasto mais?', Icons.donut_large_outlined),
    ('Quanto posso gastar?', Icons.account_balance_wallet_outlined),
    ('Compara com o mês passado', Icons.compare_arrows_rounded),
    ('Que contas tenho para pagar?', Icons.event_outlined),
    ('Como vão os meus objetivos?', Icons.flag_outlined),
  ];

  final _question = TextEditingController();
  final _focus = FocusNode();
  String? _asked;
  AskAnswer? _answer;
  bool _thinking = false;

  @override
  void dispose() {
    _question.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _ask([String? preset]) async {
    final q = (preset ?? _question.text).trim();
    if (q.isEmpty || _thinking) return;
    _focus.unfocus();
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _asked = q;
      _thinking = true;
      _question.clear();
    });
    // Um instante de "a pensar": a resposta é instantânea, mas a transição
    // dá tempo ao olho para acompanhar.
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    setState(() {
      _answer = widget.engine().ask(q);
      _thinking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Barra de pergunta em forma de cápsula, com brilho da IA.
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(colors: [colors.aiAccent.withValues(alpha: 0.7), scheme.primary.withValues(alpha: 0.7)]),
            boxShadow: [BoxShadow(color: colors.aiAccent.withValues(alpha: 0.25), blurRadius: 24, spreadRadius: -8)],
          ),
          padding: const EdgeInsets.all(1.5),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(31),
            ),
            child: Row(
              children: [
                const SizedBox(width: FtSpace.md),
                Icon(Icons.auto_awesome, color: colors.aiAccent, size: 22),
                const SizedBox(width: FtSpace.sm),
                Expanded(
                  child: TextField(
                    key: const Key('ask-question'),
                    controller: _question,
                    focusNode: _focus,
                    maxLength: 200,
                    textInputAction: TextInputAction.search,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _ask(),
                    decoration: const InputDecoration(
                      hintText: 'Pergunte ao FINTRACK…',
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: IconButton.filled(
                    key: const Key('ask-send'),
                    tooltip: 'Perguntar',
                    style: IconButton.styleFrom(backgroundColor: colors.aiAccent, foregroundColor: Colors.black),
                    icon: const Icon(Icons.arrow_upward_rounded),
                    onPressed: _ask,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: FtSpace.sm),
        // Sugestões que deslizam na horizontal.
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: FtSpace.sm),
            itemBuilder: (context, i) {
              final (label, icon) = _chips[i];
              return ActionChip(
                avatar: Icon(icon, size: 16, color: colors.aiAccent),
                label: Text(label),
                shape: const StadiumBorder(),
                side: BorderSide(color: colors.aiAccent.withValues(alpha: 0.3)),
                backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
                onPressed: () => _ask(label),
              );
            },
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: _thinking
                ? Padding(
                    key: const ValueKey('thinking'),
                    padding: const EdgeInsets.only(top: FtSpace.md),
                    child: _Thinking(color: colors.aiAccent),
                  )
                : _answer == null
                    ? const SizedBox(key: ValueKey('none'), width: double.infinity)
                    : Padding(
                        key: ValueKey(_asked),
                        padding: const EdgeInsets.only(top: FtSpace.md),
                        child: _AnswerCard(
                          question: _asked!,
                          answer: _answer!,
                          discreet: widget.discreet,
                          onAsk: _ask,
                        ),
                      ),
          ),
        ),
      ],
    );
  }
}

/// Três pontos a respirar enquanto a resposta chega.
class _Thinking extends StatelessWidget {
  const _Thinking({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var i = 0; i < 3; i++)
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.3, end: 1),
          duration: Duration(milliseconds: 220 + i * 60),
          builder: (context, v, _) => Container(
            margin: const EdgeInsets.only(right: 6),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color.withValues(alpha: v), shape: BoxShape.circle),
          ),
        ),
      Text('A analisar os seus movimentos…', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.question, required this.answer, required this.discreet, required this.onAsk});

  final String question;
  final AskAnswer answer;
  final bool discreet;
  final void Function(String) onAsk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final a = answer;
    final maxBar = a.bars.fold<int>(1, (m, b) => math.max(m, b.$2.minor.abs()));

    return GlowPanel(
      glow: colors.aiAccent,
      child: Column(
        key: const Key('ask-answer'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: colors.aiAccent),
            const SizedBox(width: 4),
            Expanded(child: Text(question, style: muted?.copyWith(fontStyle: FontStyle.italic))),
          ]),
          const SizedBox(height: FtSpace.sm),
          if (a.headline != null) ...[
            if (a.headlineLabel != null) Text(discreet ? _hide(a.headlineLabel!) : a.headlineLabel!, style: muted),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CountUpMoney(
                money: a.headline!,
                discreet: discreet,
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: FtSpace.sm),
          ],
          Text(discreet && a.understood ? _hide(a.text) : a.text, style: theme.textTheme.bodyLarge),
          if (a.bars.isNotEmpty) ...[
            const SizedBox(height: FtSpace.md),
            for (final (i, (label, value)) in a.bars.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: FtSpace.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                      Text(discreet ? '••••' : value.format(),
                          style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: ftAmountFeatures)),
                    ]),
                    const SizedBox(height: 4),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: value.minor.abs() / maxBar),
                      duration: Duration(milliseconds: 600 + i * 120),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: v,
                          minHeight: 6,
                          backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                          valueColor: AlwaysStoppedAnimation(
                            Color.lerp(colors.aiAccent, theme.colorScheme.primary, i / math.max(1, a.bars.length - 1))!,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ] else
            for (final l in a.lines)
              Padding(
                padding: const EdgeInsets.only(top: FtSpace.xs),
                child: a.understood
                    ? Text('•  ${discreet ? _hide(l) : l}', style: theme.textTheme.bodyMedium)
                    : ActionChip(label: Text(l), onPressed: () => onAsk(l)),
              ),
        ],
      ),
    );
  }
}

// --- Observações em carrossel -----------------------------------------------------

class InsightCarousel extends StatefulWidget {
  const InsightCarousel({super.key, required this.insights, required this.discreet});

  final List<Insight> insights;
  final bool discreet;

  @override
  State<InsightCarousel> createState() => _InsightCarouselState();
}

class _InsightCarouselState extends State<InsightCarousel> {
  final _pages = PageController(viewportFraction: 0.88);
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final list = widget.insights;
    return Column(
      children: [
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _pages,
            padEnds: false,
            itemCount: list.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              final ins = list[i];
              final (tone, icon) = switch (ins.tone) {
                InsightTone.good => (colors.income, Icons.verified_outlined),
                InsightTone.warning => (colors.alert, Icons.bolt_rounded),
                InsightTone.info => (colors.aiAccent, Icons.lightbulb_outline_rounded),
              };
              return AnimatedScale(
                scale: i == _page ? 1 : 0.94,
                duration: const Duration(milliseconds: 250),
                child: Padding(
                  padding: const EdgeInsets.only(right: FtSpace.sm),
                  child: GlowPanel(
                    glow: tone,
                    strong: i == _page,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: tone.withValues(alpha: 0.16), shape: BoxShape.circle),
                          child: Icon(icon, size: 18, color: tone),
                        ),
                        const SizedBox(height: FtSpace.sm),
                        Text(
                          widget.discreet ? _hide(ins.title) : ins.title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Expanded(
                          child: Text(
                            widget.discreet ? _hide(ins.detail) : ins.detail,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            overflow: TextOverflow.fade,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (list.length > 1) ...[
          const SizedBox(height: FtSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < list.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? colors.aiAccent : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// --- Tendências: curvas animadas ----------------------------------------------------

class TrendChart extends StatefulWidget {
  const TrendChart({super.key, required this.data, required this.currency, required this.discreet});

  final FinanceData data;
  final Currency currency;
  final bool discreet;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  static const _abbr = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final months = TrendsEngine.months(widget.data.ledger, widget.currency, today: DateTime.now());
    final empty = months.every((m) => m.income.isZero && m.expense.isZero);
    final sel = _selected ?? months.length - 1;
    final m = months[sel];

    return GlowPanel(
      glow: colors.aiAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.show_chart_rounded, color: colors.aiAccent),
            const SizedBox(width: FtSpace.sm),
            Expanded(child: Text('Tendência de 6 meses', style: theme.textTheme.titleMedium)),
            Text(widget.currency.code, style: muted),
          ]),
          if (empty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: FtSpace.lg),
              child: Text('Registe movimentos para ver a evolução aqui.', style: muted),
            )
          else ...[
            const SizedBox(height: FtSpace.md),
            // Mês selecionado: entradas, saídas e saldo do mês.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Row(
                key: ValueKey(sel),
                children: [
                  _Stat(label: 'Entradas', money: m.income, color: colors.income, discreet: widget.discreet),
                  _Stat(label: 'Saídas', money: m.expense, color: colors.expense, discreet: widget.discreet),
                  _Stat(
                    label: 'Saldo de ${_abbr[m.month.month - 1]}',
                    money: m.net,
                    color: m.net.minor >= 0 ? colors.income : colors.expense,
                    discreet: widget.discreet,
                  ),
                ],
              ),
            ),
            const SizedBox(height: FtSpace.md),
            LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) {
                  final i = (d.localPosition.dx / box.maxWidth * months.length).floor().clamp(0, months.length - 1);
                  HapticFeedback.selectionClick();
                  setState(() => _selected = i);
                },
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 1200),
                  curve: Curves.easeInOutCubic,
                  builder: (context, t, _) => CustomPaint(
                    size: Size(box.maxWidth, 140),
                    painter: _CurvesPainter(
                      income: [for (final x in months) x.income.minor.toDouble()],
                      expense: [for (final x in months) x.expense.minor.toDouble()],
                      incomeColor: colors.income,
                      expenseColor: colors.expense,
                      grid: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                      progress: t,
                      selected: sel,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: FtSpace.xs),
            Row(children: [
              for (final (i, x) in months.indexed)
                Expanded(
                  child: Text(
                    _abbr[x.month.month - 1],
                    textAlign: TextAlign.center,
                    style: muted?.copyWith(
                      color: i == sel ? theme.colorScheme.onSurface : null,
                      fontWeight: i == sel ? FontWeight.w700 : null,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: FtSpace.xs),
            Text('Toque num mês para ver os valores.', style: muted, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.money, required this.color, required this.discreet});

  final String label;
  final Money money;
  final Color color;
  final bool discreet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Flexible(child: Text(label, style: theme.textTheme.labelSmall, overflow: TextOverflow.ellipsis)),
          ]),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              discreet ? '••••' : money.format(withSymbol: false),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: ftAmountFeatures),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurvesPainter extends CustomPainter {
  _CurvesPainter({
    required this.income,
    required this.expense,
    required this.incomeColor,
    required this.expenseColor,
    required this.grid,
    required this.progress,
    required this.selected,
  });

  final List<double> income;
  final List<double> expense;
  final Color incomeColor;
  final Color expenseColor;
  final Color grid;
  final double progress;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    final n = income.length;
    final maxV = [...income, ...expense, 1.0].reduce(math.max);
    final step = size.width / n;
    final top = 10.0, bottom = size.height - 6;

    // Grelha discreta.
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = top + (bottom - top) * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }

    // Coluna do mês selecionado.
    final sx = step * selected;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(sx + 4, 0, step - 8, size.height), const Radius.circular(12)),
      Paint()..color = grid.withValues(alpha: 0.10),
    );

    Offset pt(int i, double v) => Offset(step * i + step / 2, bottom - (bottom - top) * (v / maxV) * progress);

    void curve(List<double> values, Color color) {
      final pts = [for (var i = 0; i < n; i++) pt(i, values[i])];
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < n; i++) {
        final a = pts[i - 1], b = pts[i];
        final mx = (a.dx + b.dx) / 2;
        path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
      }
      final fill = Path.from(path)
        ..lineTo(pts.last.dx, bottom)
        ..lineTo(pts.first.dx, bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ).createShader(Rect.fromLTRB(0, top, size.width, bottom)),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      final p = pts[selected];
      canvas.drawCircle(p, 6, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(p, 3.5, Paint()..color = color);
    }

    curve(income, incomeColor);
    curve(expense, expenseColor);
  }

  @override
  bool shouldRepaint(_CurvesPainter old) =>
      old.progress != progress || old.selected != selected || old.income != income || old.expense != expense;
}

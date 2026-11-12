import 'dart:async';

import 'package:flutter/material.dart';

import '../design/tokens.dart';

enum TipTopic { finance, saving, investing }

class Tip {
  const Tip(this.topic, this.text);
  final TipTopic topic;
  final String text;
}

String tipTopicLabel(TipTopic t) => switch (t) {
      TipTopic.finance => 'Finanças',
      TipTopic.saving => 'Poupança',
      TipTopic.investing => 'Investimento',
    };

/// Dicas educativas e gerais. Não são aconselhamento financeiro profissional.
const tips = <Tip>[
  Tip(TipTopic.saving, 'Pague-se primeiro: separe a poupança no dia em que o salário entra, não no fim do mês.'),
  Tip(TipTopic.saving, 'Uma reserva de emergência de 3 a 6 meses de despesas protege-o de imprevistos sem recorrer a crédito.'),
  Tip(TipTopic.finance, 'A regra 50/30/20 é um bom ponto de partida: necessidades, desejos e poupança.'),
  Tip(TipTopic.finance, 'Registe as pequenas despesas. Somadas ao fim do mês, costumam surpreender.'),
  Tip(TipTopic.saving, 'Antes de uma compra por impulso, espere 24 horas. Se ainda fizer sentido, compre.'),
  Tip(TipTopic.investing, 'Diversificar reduz o risco: não concentre todas as poupanças num único ativo.'),
  Tip(TipTopic.investing, 'Juros compostos premiam o tempo: começar cedo pesa mais do que começar com muito.'),
  Tip(TipTopic.investing, 'Os títulos do Tesouro (OT e BT) são uma forma de investir em dívida pública angolana.'),
  Tip(TipTopic.investing, 'A BODIVA é a bolsa angolana: informe-se sobre os produtos e custos junto de um intermediário autorizado.'),
  Tip(TipTopic.investing, 'Compare a rentabilidade com a inflação: o que importa é quanto o dinheiro ganha em poder de compra.'),
  Tip(TipTopic.finance, 'Dívidas com juros altos primeiro: pagá-las é um "investimento" com retorno garantido.'),
  Tip(TipTopic.finance, 'Reveja as subscrições e pacotes mensais: cancele o que já não usa.'),
  Tip(TipTopic.saving, 'Defina objetivos com valor e prazo. Poupar "para algo" é mais fácil do que poupar "por poupar".'),
  Tip(TipTopic.saving, 'Na Kixikila, combine regras claras por escrito: valores, datas e ordem de recebimento.'),
  Tip(TipTopic.finance, 'Separe o dinheiro do negócio do dinheiro pessoal, mesmo num negócio pequeno.'),
  Tip(TipTopic.finance, 'Compare o saldo do FINTRACK com o extrato do banco uma vez por mês.'),
  Tip(TipTopic.saving, 'Automatize: uma transferência fixa para a poupança evita depender da força de vontade.'),
  Tip(TipTopic.investing, 'Desconfie de promessas de lucros altos e garantidos. Rentabilidade alta implica risco alto.'),
  Tip(TipTopic.finance, 'Câmbio: registe sempre a taxa usada e a data. Ajuda a perceber quanto custou de verdade.'),
  Tip(TipTopic.saving, 'Compre a granel o que é básico e não perecível: o preço por unidade costuma ser menor.'),
  Tip(TipTopic.finance, 'Antes de pedir crédito, calcule a prestação como percentagem do rendimento mensal.'),
  Tip(TipTopic.investing, 'Invista apenas o dinheiro de que não vai precisar a curto prazo.'),
  Tip(TipTopic.saving, 'Aumentos de rendimento são a melhor altura para aumentar a percentagem que poupa.'),
  Tip(TipTopic.finance, 'Planeie as despesas anuais (escola, seguros, festas) e divida-as por 12 meses.'),
  Tip(TipTopic.investing, 'Conheça a sua tolerância ao risco antes de escolher onde investir.'),
  Tip(TipTopic.finance, 'Guarde os recibos importantes: garantias, impostos e devoluções agradecem.'),
  Tip(TipTopic.saving, 'Cozinhar em casa mais vezes é das formas mais simples de reduzir despesas.'),
  Tip(TipTopic.investing, 'Reinvestir os rendimentos acelera o crescimento de um investimento ao longo dos anos.'),
  Tip(TipTopic.finance, 'Um orçamento não é uma prisão: é um plano. Ajuste-o quando a vida mudar.'),
  Tip(TipTopic.saving, 'Celebre os marcos: atingir 25% de um objetivo também merece reconhecimento.'),
];

/// Faixa discreta com uma dica que muda sozinha. Tocar avança; tocar longo
/// mostra todas.
class TipsTicker extends StatefulWidget {
  const TipsTicker({super.key, this.interval = const Duration(seconds: 9)});

  final Duration interval;

  @override
  State<TipsTicker> createState() => _TipsTickerState();
}

class _TipsTickerState extends State<TipsTicker> {
  // Começa numa dica diferente a cada dia.
  late int _index = DateTime.now().difference(DateTime(2026)).inDays % tips.length;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) => _next());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _next() {
    if (mounted) setState(() => _index = (_index + 1) % tips.length);
  }

  void _showAll() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(FtSpace.lg, 0, FtSpace.lg, FtSpace.lg),
            children: [
              Text('Dicas', style: theme.textTheme.titleLarge),
              const SizedBox(height: FtSpace.xs),
              Text(
                'Conteúdo educativo e geral. Não constitui aconselhamento financeiro profissional.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: FtSpace.md),
              for (final t in tips)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.text),
                  subtitle: Text(tipTopicLabel(t.topic)),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tip = tips[_index];
    final muted = theme.colorScheme.onSurfaceVariant;

    return Semantics(
      label: 'Dica de ${tipTopicLabel(tip.topic)}: ${tip.text}',
      button: true,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(FtRadius.md),
        onTap: _next,
        onLongPress: _showAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: FtSpace.sm, horizontal: FtSpace.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_outlined, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: FtSpace.sm),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
                          .animate(animation),
                      child: child,
                    ),
                  ),
                  child: Column(
                    key: ValueKey(_index),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tipTopicLabel(tip.topic).toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tip.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

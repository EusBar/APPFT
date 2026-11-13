import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud/account_screen.dart';
import '../cloud/cloud_controller.dart';
import '../design/tokens.dart';
import '../finance/finance_data.dart';
import '../security/session.dart';
import 'copilot_api.dart';
import 'copilot_context.dart';

/// Copilot: perguntas em linguagem natural sobre as próprias finanças.
///
/// Só com conta FINTRACK e autorização expressa. O telemóvel calcula um
/// resumo dos números; a resposta só é mostrada como verificada se cada valor
/// existir nesse resumo (regra de ouro).
class CopilotCard extends ConsumerStatefulWidget {
  const CopilotCard({super.key, required this.data});

  final FinanceData data;

  @override
  ConsumerState<CopilotCard> createState() => _CopilotCardState();
}

class _CopilotCardState extends ConsumerState<CopilotCard> {
  static const _kConsent = 'ai.copilotConsent';
  static const _suggestions = [
    'Quanto gastei este mês?',
    'Em que categoria gasto mais?',
    'Consigo pagar as contas até ao fim do mês?',
    'Como vão os meus objetivos?',
  ];

  final _question = TextEditingController();
  final List<CopilotTurn> _turns = [];
  bool? _consent;
  bool _asking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConsent();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _loadConsent() async {
    final v = await ref.read(sessionProvider.notifier).store?.getSetting(_kConsent);
    if (mounted) setState(() => _consent = v == '1');
  }

  Future<void> _setConsent(bool on) async {
    await ref.read(sessionProvider.notifier).store?.setSetting(_kConsent, on ? '1' : null);
    if (mounted) {
      setState(() {
        _consent = on;
        if (!on) _turns.clear();
      });
    }
  }

  Future<void> _askConsent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.auto_awesome),
        title: const Text('Ativar o Copilot?'),
        content: const SingleChildScrollView(
          child: Text(
            'Para responder, o FINTRACK envia ao serviço de IA (Claude, da Anthropic), através do '
            'nosso servidor, um resumo dos seus números: saldos e nomes das contas, totais por '
            'categoria dos últimos 3 meses, compromissos, orçamentos e objetivos.\n\n'
            'Não envia descrições de movimentos, observações, fotografias, o seu e-mail nem nomes '
            'de pessoas. As perguntas não são guardadas pelo FINTRACK nem usadas para treinar a IA.\n\n'
            'Pode desligar quando quiser.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Agora não')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Autorizo')),
        ],
      ),
    );
    if (ok == true) await _setConsent(true);
  }

  Future<void> _ask([String? preset]) async {
    final question = (preset ?? _question.text).trim();
    if (question.isEmpty || _asking) return;
    FocusScope.of(context).unfocus();
    final session = ref.read(sessionProvider);
    final summary = copilotContext(widget.data, today: DateTime.now(), horizon: session.horizon);
    final history = List.of(_turns);
    setState(() {
      _asking = true;
      _error = null;
      _turns.add(CopilotTurn(fromUser: true, text: question));
      _question.clear();
    });
    try {
      final token = await ref.read(cloudProvider.notifier).accessToken();
      if (token == null) throw const CopilotException('Entre na sua conta FINTRACK para usar o Copilot.');
      final answer = await ref.read(copilotApiProvider).ask(
            accessToken: token,
            question: question,
            context: summary,
            history: history,
          );
      final unverified = NumberValidator([summary]).unverified(answer);
      if (mounted) setState(() => _turns.add(CopilotTurn(fromUser: false, text: answer, unverified: unverified)));
    } on CopilotException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível falar com o Copilot. Tente de novo.');
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FtColors>()!;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final signedIn = ref.watch(cloudProvider.select((c) => c.signedIn));

    final header = Row(
      children: [
        Icon(Icons.forum_outlined, color: colors.aiAccent),
        const SizedBox(width: FtSpace.sm),
        Expanded(child: Text('Copilot', style: theme.textTheme.titleMedium)),
        if (signedIn && _consent == true)
          PopupMenuButton<String>(
            tooltip: 'Opções do Copilot',
            onSelected: (v) {
              if (v == 'clear') setState(_turns.clear);
              if (v == 'off') _setConsent(false);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Limpar conversa')),
              PopupMenuItem(value: 'off', child: Text('Desligar o Copilot')),
            ],
          ),
      ],
    );

    final List<Widget> body;
    if (!signedIn) {
      body = [
        Text('Pergunte em português sobre o seu dinheiro e receba respostas com os seus números.', style: muted),
        const SizedBox(height: FtSpace.sm),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.login),
          label: const Text('Entrar na conta para usar'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
          ),
        ),
      ];
    } else if (_consent != true) {
      body = [
        Text(
          'Pergunte em português sobre o seu dinheiro: "Quanto gastei em transporte?", '
          '"Consigo poupar 50 000 Kz este mês?". Usa IA na nuvem, só com a sua autorização.',
          style: muted,
        ),
        const SizedBox(height: FtSpace.sm),
        FilledButton.tonalIcon(
          key: const Key('copilot-enable'),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Ativar o Copilot'),
          onPressed: _consent == null ? null : _askConsent,
        ),
      ];
    } else {
      body = [
        if (_turns.isEmpty) ...[
          Text('Experimente:', style: muted),
          const SizedBox(height: FtSpace.xs),
          Wrap(
            spacing: FtSpace.sm,
            runSpacing: FtSpace.xs,
            children: [
              for (final s in _suggestions)
                ActionChip(label: Text(s), onPressed: _asking ? null : () => _ask(s)),
            ],
          ),
        ],
        for (final t in _turns) _Bubble(turn: t),
        if (_asking)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FtSpace.sm),
            child: Row(children: [
              Icon(Icons.more_horiz, color: colors.aiAccent),
              const SizedBox(width: FtSpace.sm),
              Text('A analisar os seus números…', style: muted),
            ]),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: FtSpace.sm),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: FtSpace.sm),
        TextField(
          key: const Key('copilot-question'),
          controller: _question,
          maxLength: 500,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.send,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _ask(),
          decoration: InputDecoration(
            hintText: 'Pergunte sobre as suas finanças…',
            border: const OutlineInputBorder(),
            counterText: '',
            suffixIcon: IconButton(
              key: const Key('copilot-send'),
              tooltip: 'Enviar',
              icon: const Icon(Icons.send),
              onPressed: _asking ? null : _ask,
            ),
          ),
        ),
        const SizedBox(height: FtSpace.xs),
        Text('Respostas geradas por IA a partir de um resumo dos seus dados. Confirme valores importantes.', style: muted),
      ];
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(FtRadius.lg),
        border: Border.all(color: colors.aiAccent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FtSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, const SizedBox(height: FtSpace.xs), ...body],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.turn});

  final CopilotTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mine = turn.fromUser;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: FtSpace.sm),
        padding: const EdgeInsets.symmetric(horizontal: FtSpace.md, vertical: FtSpace.sm),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: mine ? scheme.primary.withValues(alpha: 0.18) : scheme.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(FtRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(turn.text),
            if (turn.unverified.isNotEmpty) ...[
              const SizedBox(height: FtSpace.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                  const SizedBox(width: FtSpace.xs),
                  Expanded(
                    child: Text(
                      'Atenção: ${turn.unverified.join(', ')} não ${turn.unverified.length == 1 ? 'aparece' : 'aparecem'} '
                      'nos seus dados. Confirme antes de decidir.',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/backdrop.dart';
import '../design/tokens.dart';
import '../security/session.dart';
import 'account_screen.dart';

/// Vitrine depois de terminar a sessão: fotografias em transição, as
/// vantagens do FINTRACK e o caminho para entrar ou criar conta.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _Slide {
  const _Slide(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;
}

const _slides = [
  _Slide(Icons.account_balance_wallet_outlined, 'Saiba quanto pode gastar',
      'O saldo disponível já desconta as contas a pagar até ao fim do mês. Sem surpresas.'),
  _Slide(Icons.bolt_outlined, 'Registe em segundos',
      'Escreva "almoço 3500" e a IA prepara o movimento. Só tem de confirmar.'),
  _Slide(Icons.flag_outlined, 'Planeie com calma',
      'Orçamentos, objetivos e Kixikila num só lugar, com avisos antes de cada pagamento.'),
  _Slide(Icons.insights_outlined, 'Perceba para onde vai o dinheiro',
      'Relatórios do mês claros e alertas quando um gasto sai do normal.'),
  _Slide(Icons.lock_outline, 'Privacidade de banco',
      'PIN, biometria e cifra ponta-a-ponta: nem o FINTRACK consegue ler os seus dados.'),
  _Slide(Icons.devices_outlined, 'Em qualquer telemóvel',
      'Perdeu o telemóvel? Entre noutro com a sua conta e recupera tudo.'),
];

const _photos = [
  'assets/backgrounds/savings.jpg',
  'assets/backgrounds/shopping.jpg',
  'assets/backgrounds/payment.jpg',
  'assets/backgrounds/analytics.jpg',
  'assets/backgrounds/lock.jpg',
];

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pages = PageController();
  int _page = 0;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    // Respeita quem pediu menos animação no sistema.
    if (MediaQuery.disableAnimationsOf(context)) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pages.hasClients) return;
      _pages.animateToPage(
        (_page + 1) % _slides.length,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _open({required bool create}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AccountScreen(entry: true, startCreate: create),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: RotatingBackdrop(
        assets: _photos,
        strength: FtBackdropStrength.normal,
        interval: const Duration(seconds: 6),
        child: SafeArea(
          child: LayoutBuilder(
            // Em ecrãs baixos, desliza; nos outros, ocupa o ecrã todo.
            builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: FtSpace.lg),
            child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: FtSpace.xl),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(FtRadius.md),
                      ),
                      child: Icon(Icons.insights, color: scheme.onPrimary),
                    ),
                    const SizedBox(width: FtSpace.md),
                    Flexible(
                      child: Text('FINTRACK', style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: FtSpace.lg),
                Text(
                  'O seu dinheiro,\nclaro e seguro.',
                  style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, height: 1.15),
                ),
                const SizedBox(height: FtSpace.sm),
                Text(
                  'Controle gastos, planeie o mês e poupe mais, em poucos toques por dia.',
                  style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
                ]),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: FtSpace.lg),
                  child: Column(children: [
                SizedBox(
                  height: 150,
                  child: PageView.builder(
                    key: const Key('welcome-slides'),
                    controller: _pages,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => _SlideCard(slide: _slides[i]),
                  ),
                ),
                const SizedBox(height: FtSpace.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _slides.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _page ? scheme.primary : scheme.onSurface.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton(
                  key: const Key('welcome-create'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => _open(create: true),
                  child: const Text('Criar conta grátis'),
                ),
                const SizedBox(height: FtSpace.sm),
                OutlinedButton(
                  key: const Key('welcome-signin'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => _open(create: false),
                  child: const Text('Já tenho conta · Entrar'),
                ),
                TextButton(
                  key: const Key('start-without-account'),
                  onPressed: () => ref.read(sessionProvider.notifier).startWithoutAccount(),
                  child: const Text('Começar sem conta, só neste telemóvel'),
                ),
                const SizedBox(height: FtSpace.sm),
                ]),
              ],
            ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(FtRadius.lg),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(FtSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.primary.withValues(alpha: 0.18),
                child: Icon(slide.icon, color: scheme.primary),
              ),
              const SizedBox(width: FtSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(slide.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: FtSpace.xs),
                    Text(
                      slide.text,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

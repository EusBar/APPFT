import 'dart:async';

import 'package:flutter/material.dart';

/// Fotografias de fundo (Unsplash, licença Unsplash), já desfocadas e
/// reduzidas para pesar pouco em telemóveis de gama baixa.
enum FtImage {
  lock('assets/backgrounds/lock.jpg'),
  createPin('assets/backgrounds/create_pin.jpg'),
  savings('assets/backgrounds/savings.jpg'),
  shopping('assets/backgrounds/shopping.jpg'),
  payment('assets/backgrounds/payment.jpg'),
  analytics('assets/backgrounds/analytics.jpg');

  const FtImage(this.asset);
  final String asset;
}

/// Fundo premium: fotografia desfocada sob um véu da cor de fundo do tema,
/// mais denso em baixo para o texto e os valores se lerem sempre bem.
class FtBackdrop extends StatelessWidget {
  FtBackdrop({
    super.key,
    required FtImage image,
    required this.child,
    this.strength = FtBackdropStrength.normal,
  }) : asset = image.asset;

  /// Fundo com qualquer fotografia dos assets (ex.: ponto turístico).
  const FtBackdrop.asset({
    super.key,
    required this.asset,
    required this.child,
    this.strength = FtBackdropStrength.normal,
  });

  final String asset;
  final Widget child;
  final FtBackdropStrength strength;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final (top, middle, bottom) = switch (strength) {
      FtBackdropStrength.normal => (0.62, 0.80, 0.96),
      FtBackdropStrength.subtle => (0.78, 0.92, 1.0),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: surface),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 1200),
          child: Image.asset(
            asset,
            key: ValueKey(asset),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            excludeFromSemantics: true,
            gaplessPlayback: true,
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.45, 1],
              colors: [
                surface.withValues(alpha: top),
                surface.withValues(alpha: middle),
                surface.withValues(alpha: bottom),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

enum FtBackdropStrength {
  /// Ecrãs de entrada (PIN, onboarding): a imagem nota-se mais.
  normal,

  /// Ecrãs com muitos valores: a imagem fica só sugerida.
  subtle,
}

/// Fundo que passa devagar por várias fotografias, com fundido suave.
class RotatingBackdrop extends StatefulWidget {
  const RotatingBackdrop({
    super.key,
    required this.assets,
    required this.child,
    this.fallback = FtImage.analytics,
    this.strength = FtBackdropStrength.subtle,
    this.interval = const Duration(seconds: 20),
  });

  final List<String> assets;
  final FtImage fallback;
  final Widget child;
  final FtBackdropStrength strength;
  final Duration interval;

  @override
  State<RotatingBackdrop> createState() => _RotatingBackdropState();
}

class _RotatingBackdropState extends State<RotatingBackdrop> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(RotatingBackdrop old) {
    super.didUpdateWidget(old);
    if (old.assets.join() != widget.assets.join()) {
      _index = 0;
      _restart();
    }
  }

  void _restart() {
    _timer?.cancel();
    if (widget.assets.length < 2) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _index = (_index + 1) % widget.assets.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = widget.assets;
    return FtBackdrop.asset(
      asset: assets.isEmpty ? widget.fallback.asset : assets[_index % assets.length],
      strength: widget.strength,
      child: widget.child,
    );
  }
}

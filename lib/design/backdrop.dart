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
  })  : asset = image.asset,
        caption = null;

  /// Fundo com qualquer fotografia dos assets (ex.: ponto turístico).
  const FtBackdrop.asset({
    super.key,
    required this.asset,
    required this.child,
    this.strength = FtBackdropStrength.normal,
    this.caption,
  });

  final String asset;
  final Widget child;
  final FtBackdropStrength strength;

  /// Camada entre a fotografia e o conteúdo (ex.: nome do lugar).
  final Widget? caption;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final (top, middle, bottom) = switch (strength) {
      FtBackdropStrength.normal => (0.62, 0.80, 0.96),
      FtBackdropStrength.subtle => (0.78, 0.92, 1.0),
      FtBackdropStrength.scenic => (0.38, 0.62, 0.90),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: surface),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 2500),
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
        if (caption != null) caption!,
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

  /// Paisagens no uso diário: a fotografia mostra-se, o fundo escurece em
  /// baixo, onde ficam os valores.
  scenic,
}

/// Fundo que passa devagar por várias fotografias, com fundido suave.
class RotatingBackdrop extends StatefulWidget {
  const RotatingBackdrop({
    super.key,
    required this.assets,
    required this.child,
    this.fallback = FtImage.analytics,
    this.strength = FtBackdropStrength.subtle,
    // Muda o suficiente para se notar, sem distrair do que se está a fazer.
    this.interval = const Duration(seconds: 30),
    this.captions,
    this.captionBottom = 96,
    this.captionAtTop = false,
  });

  final List<String> assets;

  /// Nome do lugar de cada fotografia (mesma ordem de [assets]).
  final List<String>? captions;

  /// Distância ao fundo (acima da barra de navegação).
  final double captionBottom;
  final bool captionAtTop;
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
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.assets.length);
      // Prepara já a seguinte, para o fundido não piscar.
      final next = widget.assets[(_index + 1) % widget.assets.length];
      precacheImage(AssetImage(next), context).ignore();
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
    final captions = widget.captions;
    final place = captions == null || captions.isEmpty ? null : captions[_index % captions.length];
    final insets = MediaQuery.paddingOf(context);
    return FtBackdrop.asset(
      asset: assets.isEmpty ? widget.fallback.asset : assets[_index % assets.length],
      strength: widget.strength,
      caption: place == null
          ? null
          : Positioned(
              left: 16,
              right: 16,
              top: widget.captionAtTop ? insets.top + 8 : null,
              bottom: widget.captionAtTop ? null : insets.bottom + widget.captionBottom,
              child: Align(
                alignment: widget.captionAtTop ? Alignment.topRight : Alignment.bottomLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 1200),
                  child: _PlaceTag(key: ValueKey(place), place: place),
                ),
              ),
            ),
      child: widget.child,
    );
  }
}

/// Nome do lugar, escrito na própria fotografia (como a legenda de um
/// fotógrafo): fica por baixo do conteúdo e nunca o tapa.
class _PlaceTag extends StatelessWidget {
  const _PlaceTag({super.key, required this.place});

  final String place;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Colors.black87, blurRadius: 8)];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.place_outlined, size: 13, color: Colors.white70, shadows: shadow),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          place,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            inherit: false,
            color: Colors.white70,
            fontSize: 12,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.3,
            shadows: shadow,
          ),
        ),
      ),
    ]);
  }
}

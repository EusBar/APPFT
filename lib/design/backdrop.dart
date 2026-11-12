import 'package:flutter/material.dart';

import 'tokens.dart';

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
  const FtBackdrop({
    super.key,
    required this.image,
    required this.child,
    this.strength = FtBackdropStrength.normal,
  });

  final FtImage image;
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
          duration: FtMotion.slow,
          child: Image.asset(
            image.asset,
            key: ValueKey(image),
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

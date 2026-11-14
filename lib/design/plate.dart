import 'package:flutter/material.dart';

import 'tokens.dart';

/// Placa escura translúcida por trás de texto: o texto ganha contraste e a
/// paisagem continua visível à volta.
class TextPlate extends StatelessWidget {
  const TextPlate({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: FtSpace.xs),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(FtRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
      // Material próprio: efeitos de toque visíveis por cima da placa.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// Etiqueta em cápsula escura, para títulos de secção e datas.
class PlateLabel extends StatelessWidget {
  const PlateLabel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

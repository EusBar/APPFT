import 'package:flutter/material.dart';

/// Espaçamento do design system (dp).
abstract final class FtSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

/// Raios de canto.
abstract final class FtRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
}

/// Durações de animação (150–300 ms).
abstract final class FtMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 300);
}

/// Área de toque mínima (acessibilidade).
const ftMinTouchTarget = 48.0;

/// Cores semânticas: o mesmo significado em todo o app.
@immutable
class FtColors extends ThemeExtension<FtColors> {
  const FtColors({
    required this.income,
    required this.expense,
    required this.transfer,
    required this.commitment,
    required this.alert,
    required this.estimate,
    required this.aiAccent,
  });

  final Color income;
  final Color expense;
  final Color transfer;
  final Color commitment;
  final Color alert;
  final Color estimate;
  final Color aiAccent;

  static const dark = FtColors(
    income: Color(0xFF34D399),
    expense: Color(0xFFF87171),
    transfer: Color(0xFF60A5FA),
    commitment: Color(0xFFFBBF24),
    alert: Color(0xFFFB923C),
    estimate: Color(0xFF94A3B8),
    aiAccent: Color(0xFFA78BFA),
  );

  static const light = FtColors(
    income: Color(0xFF047857),
    expense: Color(0xFFB91C1C),
    transfer: Color(0xFF1D4ED8),
    commitment: Color(0xFF92400E),
    alert: Color(0xFFC2410C),
    estimate: Color(0xFF475569),
    aiAccent: Color(0xFF6D28D9),
  );

  @override
  FtColors copyWith({
    Color? income,
    Color? expense,
    Color? transfer,
    Color? commitment,
    Color? alert,
    Color? estimate,
    Color? aiAccent,
  }) {
    return FtColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      transfer: transfer ?? this.transfer,
      commitment: commitment ?? this.commitment,
      alert: alert ?? this.alert,
      estimate: estimate ?? this.estimate,
      aiAccent: aiAccent ?? this.aiAccent,
    );
  }

  @override
  FtColors lerp(ThemeExtension<FtColors>? other, double t) {
    if (other is! FtColors) return this;
    return FtColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      commitment: Color.lerp(commitment, other.commitment, t)!,
      alert: Color.lerp(alert, other.alert, t)!,
      estimate: Color.lerp(estimate, other.estimate, t)!,
      aiAccent: Color.lerp(aiAccent, other.aiAccent, t)!,
    );
  }
}

/// Estilo para valores monetários: algarismos tabulares alinham colunas.
const ftAmountFeatures = [FontFeature.tabularFigures()];

ThemeData buildFintrackTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF14B8A6),
    brightness: brightness,
  ).copyWith(
    surface: dark ? const Color(0xFF0B0F14) : const Color(0xFFF7F8FA),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: [dark ? FtColors.dark : FtColors.light],
  );
}

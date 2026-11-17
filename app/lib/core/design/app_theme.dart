import 'package:flutter/material.dart';

/// The product name: a brand, so it is never translated.
/// PT: O nome do produto: uma marca, então nunca é traduzido.
abstract final class AppBrand {
  static const name = 'SnapLedger';
}

/// The spacing scale (4-point grid); widgets use these instead of loose numbers.
/// PT: A escala de espaçamento (grade de 4 pontos); widgets usam estes em vez de números soltos.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
}

/// Material 3 themes generated from one seed color, light and dark.
/// PT: Temas Material 3 gerados a partir de uma cor semente, claro e escuro.
abstract final class AppTheme {
  static const _seed = Colors.teal;
  static const _radius = 12.0;
  static const _buttonHeight = 52.0;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colors = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(_radius),
      borderSide: BorderSide(color: color, width: width),
    );
    return ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.m),
        prefixIconColor: colors.onSurfaceVariant,
        border: border(colors.outlineVariant),
        enabledBorder: border(colors.outlineVariant),
        focusedBorder: border(colors.primary, 2),
        errorBorder: border(colors.error),
        focusedErrorBorder: border(colors.error, 2),
        errorMaxLines: 3,
        errorStyle: TextStyle(color: colors.error, fontWeight: FontWeight.w500, height: 1.3),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, _buttonHeight),
          shape: shape,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: shape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

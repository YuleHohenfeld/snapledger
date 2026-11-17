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

/// The semantic "success" green, which Material 3's color scheme does not have; light and dark variants.
/// PT: O verde semântico de "sucesso", que o color scheme do Material 3 não tem; variantes clara e escura.
/// Notes: docs/code-notes/app-auth.md#successcolors
@immutable
class SuccessColors extends ThemeExtension<SuccessColors> {
  const SuccessColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
  });

  static const light = SuccessColors(
    success: Color(0xFF1B7F3B),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFB8F0C8),
    onSuccessContainer: Color(0xFF00210B),
  );

  static const dark = SuccessColors(
    success: Color(0xFF7FD99B),
    onSuccess: Color(0xFF00391A),
    successContainer: Color(0xFF0B5128),
    onSuccessContainer: Color(0xFFB8F0C8),
  );

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  /// The theme's colors, or the variant of its brightness when a test uses a bare `ThemeData`.
  /// PT: As cores do tema, ou a variante do brilho dele quando um teste usa um `ThemeData` simples.
  static SuccessColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<SuccessColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  SuccessColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
  }) => SuccessColors(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
  );

  @override
  SuccessColors lerp(SuccessColors? other, double t) {
    if (other == null) return this;
    return SuccessColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
    );
  }
}

/// Gradients and glow colors of the "AI" look (hero, orbs, scan frame, primary button); light and dark.
/// PT: Gradientes e cores de brilho do visual "AI" (hero, orbes, moldura de scan, botão principal); claro e escuro.
/// Notes: docs/code-notes/app-core.md#brandgradients
@immutable
class BrandGradients extends ThemeExtension<BrandGradients> {
  const BrandGradients({
    required this.heroGradient,
    required this.buttonGradient,
    required this.glowColor,
    required this.frameColor,
    required this.onHero,
  });

  /// The seed of the whole palette: an electric blue.
  /// PT: A semente de toda a paleta: um azul elétrico.
  static const brand = Color(0xFF2F5BEA);

  static const light = BrandGradients(
    heroGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0A2472), brand, Color(0xFFDCE7FF)],
      stops: [0, 0.75, 1],
    ),
    buttonGradient: LinearGradient(colors: [Color(0xFF1F45C8), brand]),
    glowColor: Color(0xFF7FA2FF),
    frameColor: Color(0x99FFFFFF),
    onHero: Color(0xFFFFFFFF),
  );

  static const dark = BrandGradients(
    heroGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF040A24), Color(0xFF0F2A78), Color(0xFF2F5BEA)],
      stops: [0, 0.75, 1],
    ),
    buttonGradient: LinearGradient(colors: [Color(0xFF1F45C8), brand]),
    glowColor: Color(0xFF5B8CFF),
    frameColor: Color(0x80FFFFFF),
    onHero: Color(0xFFFFFFFF),
  );

  /// Background of the hero, top (deep) to bottom (ice in light mode).
  /// PT: Fundo do hero, do topo (escuro) à base (gelo no modo claro).
  final Gradient heroGradient;
  final Gradient buttonGradient;
  final Color glowColor;

  /// Thin outlines on the gradient (scan frame, chips).
  /// PT: Contornos finos sobre o gradiente (moldura de scan, chips).
  final Color frameColor;

  /// Text and icons on the hero; white on the deep part passes WCAG AA.
  /// PT: Texto e ícones no hero; branco na parte escura passa no WCAG AA.
  final Color onHero;

  /// The theme's gradients, or the variant of its brightness when a test uses a bare `ThemeData`.
  /// PT: Os gradientes do tema, ou a variante do brilho dele quando um teste usa um `ThemeData` simples.
  static BrandGradients of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<BrandGradients>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  BrandGradients copyWith({
    Gradient? heroGradient,
    Gradient? buttonGradient,
    Color? glowColor,
    Color? frameColor,
    Color? onHero,
  }) => BrandGradients(
    heroGradient: heroGradient ?? this.heroGradient,
    buttonGradient: buttonGradient ?? this.buttonGradient,
    glowColor: glowColor ?? this.glowColor,
    frameColor: frameColor ?? this.frameColor,
    onHero: onHero ?? this.onHero,
  );

  @override
  BrandGradients lerp(BrandGradients? other, double t) {
    if (other == null) return this;
    return BrandGradients(
      heroGradient: Gradient.lerp(heroGradient, other.heroGradient, t)!,
      buttonGradient: Gradient.lerp(buttonGradient, other.buttonGradient, t)!,
      glowColor: Color.lerp(glowColor, other.glowColor, t)!,
      frameColor: Color.lerp(frameColor, other.frameColor, t)!,
      onHero: Color.lerp(onHero, other.onHero, t)!,
    );
  }
}

/// Material 3 themes generated from one seed color, light and dark.
/// PT: Temas Material 3 gerados a partir de uma cor semente, claro e escuro.
abstract final class AppTheme {
  static const _seed = BrandGradients.brand;
  static const _radius = 14.0;
  static const _buttonHeight = 52.0;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colors = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));
    const pill = StadiumBorder();
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(_radius),
      borderSide: BorderSide(color: color, width: width),
    );
    return ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      extensions: [
        if (brightness == Brightness.dark) SuccessColors.dark else SuccessColors.light,
        if (brightness == Brightness.dark) BrandGradients.dark else BrandGradients.light,
      ],
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
          shape: pill,
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

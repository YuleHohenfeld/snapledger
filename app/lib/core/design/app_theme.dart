import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_colors.dart';

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
    return theme.extension<SuccessColors>() ?? (theme.brightness == Brightness.dark ? dark : light);
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
    required this.accentGradient,
  });

  /// The brand color of the whole palette: an electric blue.
  /// PT: A cor da marca em toda a paleta: um azul elétrico.
  static const brand = AppColors.brand;

  /// Blue to cyan to violet: chart bars, the brand mark, selected underlines.
  /// PT: Azul, ciano e violeta: barras de gráfico, a marca, sublinhados de seleção.
  static const _accent = LinearGradient(colors: [brand, AppColors.cyan, AppColors.violet]);

  /// Only the fallback of a bare light `ThemeData` (some tests); the app itself is dark-only.
  /// PT: Só o fallback de um `ThemeData` claro simples (alguns testes); o app em si é só escuro.
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
    accentGradient: _accent,
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
    onHero: AppColors.onBrand,
    accentGradient: _accent,
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

  /// The blue-cyan-violet "AI" gradient of accents.
  /// PT: O gradiente "AI" azul-ciano-violeta dos acentos.
  final Gradient accentGradient;

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
    Gradient? accentGradient,
  }) => BrandGradients(
    heroGradient: heroGradient ?? this.heroGradient,
    buttonGradient: buttonGradient ?? this.buttonGradient,
    glowColor: glowColor ?? this.glowColor,
    frameColor: frameColor ?? this.frameColor,
    onHero: onHero ?? this.onHero,
    accentGradient: accentGradient ?? this.accentGradient,
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
      accentGradient: Gradient.lerp(accentGradient, other.accentGradient, t)!,
    );
  }
}

/// The Material 3 theme of the app: dark only (see the notes for why). Every component that draws a surface
/// (cards, dialogs, menus, sheets, date picker, snack bars, fields, bars) is themed here, so no screen can
/// fall back to a light Material default.
/// PT: O tema Material 3 do app: só escuro (veja as notas do porquê). Todo componente que desenha uma superfície
/// (cards, diálogos, menus, sheets, date picker, snack bars, campos, barras) é tematizado aqui, então nenhuma
/// tela cai num padrão claro do Material.
/// Notes: docs/code-notes/app-core.md#dark-ai-theme
abstract final class AppTheme {
  static const _radius = 14.0;
  static const _buttonHeight = 52.0;
  static const _focusRingWidth = 2.0;
  static const _fieldFillAlpha = 0.6;
  static const _focusAlpha = 0.28;
  static const _hoverAlpha = 0.10;

  /// The hand-tuned dark scheme. `surfaceTint` is transparent: elevation must not wash the navy with a tint.
  /// PT: O esquema escuro ajustado à mão. `surfaceTint` é transparente: a elevação não pode lavar o azul-marinho.
  static const colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.onPrimaryContainer,
    secondary: AppColors.cyan,
    onSecondary: AppColors.onCyan,
    secondaryContainer: AppColors.cyanContainer,
    onSecondaryContainer: AppColors.onCyanContainer,
    tertiary: AppColors.violet,
    onTertiary: AppColors.onViolet,
    tertiaryContainer: AppColors.violetContainer,
    onTertiaryContainer: AppColors.onVioletContainer,
    error: AppColors.error,
    onError: AppColors.onError,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.onErrorContainer,
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    onSurfaceVariant: AppColors.onSurfaceVariant,
    surfaceDim: AppColors.background,
    surfaceBright: AppColors.containerHighest,
    surfaceContainerLowest: AppColors.containerLowest,
    surfaceContainerLow: AppColors.containerLow,
    surfaceContainer: AppColors.container,
    surfaceContainerHigh: AppColors.containerHigh,
    surfaceContainerHighest: AppColors.containerHighest,
    outline: AppColors.outline,
    outlineVariant: AppColors.outlineVariant,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    // Snack bars use the "inverse" colors: dark glass here too, never a light bar.
    // PT: Snack bars usam as cores "inversas": vidro escuro aqui também, nunca uma barra clara.
    inverseSurface: AppColors.containerHighest,
    onInverseSurface: AppColors.onSurface,
    inversePrimary: AppColors.brand,
    surfaceTint: Colors.transparent,
  );

  /// Built once: the component themes hold closures, so two builds would never compare equal and a
  /// `MaterialApp` rebuild would start the theme-change animation for nothing.
  /// PT: Construído uma vez: os temas de componente guardam closures, então duas construções nunca seriam iguais e
  /// um rebuild do `MaterialApp` iniciaria a animação de troca de tema à toa.
  static ThemeData dark() => _dark;

  static final ThemeData _dark = _build();

  static ThemeData _build() {
    const colors = colorScheme;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));
    const pill = StadiumBorder();
    final panelShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppGlass.panelRadius),
      side: BorderSide(color: Colors.white.withValues(alpha: AppGlass.borderHighlightAlpha / 2)),
    );
    final panelColor = AppColors.container.withValues(alpha: AppGlass.panelAlpha);
    // A visible focus ring on dark: a 2px cyan outline while a button has keyboard focus.
    // PT: Um anel de foco visível no escuro: contorno ciano de 2px enquanto um botão tem o foco do teclado.
    final focusRing = WidgetStateProperty.resolveWith<BorderSide?>(
      (states) => states.contains(WidgetState.focused)
          ? const BorderSide(color: AppColors.cyan, width: _focusRingWidth)
          : null,
    );
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(_radius),
      borderSide: BorderSide(color: color, width: width),
    );
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true, colorScheme: colors);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.surface,
      focusColor: AppColors.primary.withValues(alpha: _focusAlpha),
      hoverColor: AppColors.primary.withValues(alpha: _hoverAlpha),
      dividerColor: AppColors.outlineVariant,
      extensions: const [SuccessColors.dark, BrandGradients.dark],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: panelColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: panelShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.containerHigh,
        surfaceTintColor: Colors.transparent,
        shape: panelShape,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.containerHigh,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.containerHigh,
        showDragHandle: false,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.containerHigh,
        surfaceTintColor: Colors.transparent,
        shape: panelShape,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.containerHigh),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(panelShape),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.containerHigh,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.container,
        headerForegroundColor: AppColors.onSurface,
        shape: panelShape,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.containerHighest,
        contentTextStyle: const TextStyle(color: AppColors.onSurface),
        actionTextColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: shape,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.onSurfaceVariant,
        textColor: AppColors.onSurface,
        tileColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.outlineVariant, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onBrand,
        shape: pill,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AppColors.brand.withValues(alpha: AppGlass.navIndicatorAlpha),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.onPrimaryContainer
                : AppColors.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.onSurface
                : AppColors.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.brand.withValues(alpha: AppGlass.navIndicatorAlpha),
        selectedIconTheme: const IconThemeData(color: AppColors.onPrimaryContainer),
        unselectedIconTheme: const IconThemeData(color: AppColors.onSurfaceVariant),
        selectedLabelTextStyle: const TextStyle(
          color: AppColors.onSurface,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: const TextStyle(color: AppColors.onSurfaceVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.containerHighest.withValues(alpha: _fieldFillAlpha),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.m,
        ),
        prefixIconColor: AppColors.onSurfaceVariant,
        border: border(AppColors.outlineVariant),
        enabledBorder: border(AppColors.outlineVariant),
        focusedBorder: border(AppColors.primary, 2),
        errorBorder: border(AppColors.error),
        focusedErrorBorder: border(AppColors.error, 2),
        errorMaxLines: 3,
        errorStyle: const TextStyle(
          color: AppColors.error,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, _buttonHeight),
          shape: pill,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ).copyWith(side: focusRing),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              minimumSize: const Size(64, _buttonHeight),
              shape: pill,
              side: const BorderSide(color: AppColors.outline),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? const BorderSide(color: AppColors.cyan, width: _focusRingWidth)
                    : const BorderSide(color: AppColors.outline),
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: shape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ).copyWith(side: focusRing),
      ),
    );
  }
}

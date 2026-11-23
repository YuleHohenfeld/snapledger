import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/design/app_colors.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/app_backdrop.dart';
import 'package:snapledger/core/design/widgets/aurora_background.dart';
import 'package:snapledger/core/design/widgets/glass_panel.dart';

import '../../support/pump_app.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [top] at [alpha] painted over [bottom] (what the eye sees through a translucent surface).
/// PT: [top] com [alpha] pintado sobre [bottom] (o que o olho vê através de uma superfície translúcida).
Color _over(Color top, double alpha, Color bottom) =>
    Color.alphaBlend(top.withValues(alpha: alpha), bottom);

void main() {
  final theme = AppTheme.dark();
  final scheme = theme.colorScheme;

  group('dark-only theme', () {
    test('is a dark Material 3 theme with no light surface anywhere', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
      for (final surface in [
        theme.scaffoldBackgroundColor,
        scheme.surface,
        scheme.surfaceContainerLowest,
        scheme.surfaceContainerLow,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
        scheme.inverseSurface,
        theme.dialogTheme.backgroundColor!,
        theme.bottomSheetTheme.backgroundColor!,
        theme.popupMenuTheme.color!,
        theme.datePickerTheme.backgroundColor!,
        theme.snackBarTheme.backgroundColor!,
      ]) {
        // Relative luminance well under mid-grey: a "light tone" would be far above this.
        // PT: Luminância relativa bem abaixo do cinza médio: um "tom claro" ficaria muito acima.
        expect(_luminance(surface), lessThan(0.05), reason: '$surface is too light');
      }
    });

    test('is built once, so a rebuild never starts a theme-change animation', () {
      expect(identical(AppTheme.dark(), AppTheme.dark()), isTrue);
    });

    test('keeps the brand blue for gradients and a brighter tint as primary', () {
      expect(AppColors.brand, const Color(0xFF2F5BEA));
      expect(scheme.primary, AppColors.primary);
      expect(_luminance(scheme.primary), greaterThan(_luminance(AppColors.brand)));
    });
  });

  group('contrast (WCAG AA)', () {
    // The top bar: the surface at the bar alpha over the page background (the faintest orb adds a little).
    // PT: A barra superior: a superfície com o alfa da barra sobre o fundo da página (o orbe mais fraco soma pouco).
    final topBar = _over(AppColors.surface, AppGlass.barAlpha, AppColors.background);

    // Body text and small text: 4.5:1.
    final text = <String, (Color, Color)>{
      'onSurface on background': (scheme.onSurface, AppColors.background),
      'onSurface on surface': (scheme.onSurface, scheme.surface),
      'onSurface on glass panel': (
        scheme.onSurface,
        _over(AppColors.container, AppGlass.panelAlpha, AppColors.background),
      ),
      'onSurfaceVariant on surface': (scheme.onSurfaceVariant, scheme.surface),
      'onSurfaceVariant on glass panel': (
        scheme.onSurfaceVariant,
        _over(AppColors.container, AppGlass.panelAlpha, AppColors.background),
      ),
      'onSurface on dialog / menu': (scheme.onSurface, AppColors.containerHigh),
      'onSurfaceVariant on text field': (
        scheme.onSurfaceVariant,
        _over(AppColors.containerHighest, 0.6, AppColors.surface),
      ),
      'primary text on surface': (scheme.primary, scheme.surface),
      'primary text on glass panel': (
        scheme.primary,
        _over(AppColors.container, AppGlass.panelAlpha, AppColors.background),
      ),
      'onPrimary on primary': (scheme.onPrimary, scheme.primary),
      'chip: onPrimaryContainer on primaryContainer': (
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
      ),
      'error on surface': (scheme.error, scheme.surface),
      'error on glass panel': (
        scheme.error,
        _over(AppColors.container, AppGlass.panelAlpha, AppColors.background),
      ),
      'onError on error': (scheme.onError, scheme.error),
      'onErrorContainer on errorContainer': (scheme.onErrorContainer, scheme.errorContainer),
      'success on surface': (SuccessColors.dark.success, scheme.surface),
      'white on button gradient (deep stop)': (AppColors.onBrand, const Color(0xFF1F45C8)),
      'white on button gradient (brand stop)': (AppColors.onBrand, AppColors.brand),
      'white on the total card tint (brand over surface)': (
        AppColors.onBrand,
        _over(AppColors.brand, AppGlass.totalCardBrandAlpha, AppColors.surface),
      ),
      'white on the total card tint (violet over surface)': (
        AppColors.onBrand,
        _over(AppColors.violet, AppGlass.totalCardVioletAlpha, AppColors.surface),
      ),
      'selected nav label on indicator': (
        scheme.onSurface,
        _over(AppColors.brand, AppGlass.navIndicatorAlpha, AppColors.surface),
      ),
      'selected top tab: onSurface on its fill over the bar': (
        scheme.onSurface,
        _over(scheme.primaryContainer, AppGlass.topTabSelectedAlpha, topBar),
      ),
      'unselected top tab: onSurfaceVariant on the bar': (scheme.onSurfaceVariant, topBar),
      'gradient text: bright blue on background': (AppColors.primary, AppColors.background),
      'gradient text: cyan on background': (AppColors.cyan, AppColors.background),
      'gradient text: violet on background': (AppColors.violet, AppColors.background),
    };
    for (final MapEntry(key: name, value: (foreground, background)) in text.entries) {
      test('$name is at least 4.5:1', () {
        expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
      });
    }

    // Icons, borders and focus rings: 3:1.
    final graphics = <String, (Color, Color)>{
      'outline on surface (field and button borders)': (scheme.outline, scheme.surface),
      'cyan focus ring on surface': (AppColors.cyan, scheme.surface),
      'focused field border (primary) on surface': (scheme.primary, scheme.surface),
      'brand mark / underline cyan on background': (AppColors.cyan, AppColors.background),
    };
    for (final MapEntry(key: name, value: (foreground, background)) in graphics.entries) {
      test('$name is at least 3:1', () {
        expect(_contrast(foreground, background), greaterThanOrEqualTo(3));
      });
    }
  });

  group('AuroraBackground.ambient', () {
    Widget host() => MaterialApp(
      theme: theme,
      home: const SizedBox(width: 300, height: 300, child: AuroraBackground.ambient()),
    );

    testWidgets('is static (no running ticker) when animations are disabled', (tester) async {
      reduceMotion(tester);
      await tester.pumpWidget(host());
      await tester.pump(const Duration(seconds: 2));

      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('animated: false never starts a ticker, even with motion allowed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const SizedBox(
            width: 300,
            height: 300,
            child: AuroraBackground.ambient(animated: false),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(tester.binding.transientCallbackCount, 0);
      // Nothing keeps frames coming, so this returns at once instead of timing out.
      // PT: Nada pede novos frames, então isto volta na hora em vez de estourar o tempo.
      await tester.pumpAndSettle();
    });

    testWidgets('AppBackdrop(animated: false) stays still', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const AppBackdrop(animated: false, child: Scaffold(body: Text('page'))),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('drifts otherwise, and stops when disposed', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      // Same theme: a different one would start the theme-change animation, which is a ticker too.
      // PT: Mesmo tema: outro iniciaria a animação de troca de tema, que também é um ticker.
      await tester.pumpWidget(MaterialApp(theme: theme, home: const SizedBox()));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('AppBackdrop makes a Scaffold below it transparent so the aurora shows', (
      tester,
    ) async {
      reduceMotion(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const AppBackdrop(child: Scaffold(body: Text('page'))),
        ),
      );

      final scaffold = tester.widget<Material>(
        find.descendant(of: find.byType(Scaffold), matching: find.byType(Material)).first,
      );
      expect(scaffold.color, Colors.transparent);
      expect(find.byType(AuroraBackground), findsOneWidget);
    });
  });

  testWidgets('GlassPanel paints its child above the translucent fill', (tester) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: GlassPanel(child: ListTile(title: Text('row'))),
        ),
      ),
    );

    expect(find.text('row'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

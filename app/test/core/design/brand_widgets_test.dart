import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/aurora_background.dart';
import 'package:snapledger/core/design/widgets/glow_orb.dart';
import 'package:snapledger/core/design/widgets/gradient_button.dart';
import 'package:snapledger/core/design/widgets/pill_chip.dart';
import 'package:snapledger/core/design/widgets/scan_frame.dart';

import '../../support/pump_app.dart';

double _luminance(Color c) {
  double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.light(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('AuroraBackground', () {
    testWidgets('is static (no running ticker) when animations are disabled', (tester) async {
      reduceMotion(tester);
      await tester.pumpWidget(_host(const SizedBox(width: 200, height: 200, child: AuroraBackground())));

      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('drifts otherwise, and disposes its controller with the widget', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(width: 200, height: 200, child: AuroraBackground())));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      // A ticker left alive would make the test fail on teardown ("Ticker was not disposed").
      // PT: Um ticker vivo faria o teste falhar no teardown ("Ticker was not disposed").
      await tester.pumpWidget(_host(const SizedBox()));
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  testWidgets('ScanFrame, PillChip and GlowOrb render their content', (tester) async {
    await tester.pumpWidget(
      _host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScanFrame(child: Text('frame')),
            PillChip(label: 'AI'),
            PillChip(label: 'plain', onGradient: false),
            GlowOrb(icon: Icons.check, color: Colors.green),
          ],
        ),
      ),
    );

    expect(find.text('frame'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('plain'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('GradientButton', () {
    testWidgets('taps when idle', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(GradientButton(label: 'Go', onPressed: () => taps++)));

      await tester.tap(find.widgetWithText(FilledButton, 'Go'));

      expect(taps, 1);
    });

    testWidgets('busy: disabled, spinner labeled for screen readers, no second tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(GradientButton(label: 'Go', busy: true, onPressed: () => taps++)));

      await tester.tap(find.byType(FilledButton), warnIfMissed: false);

      expect(taps, 0);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Go'), findsOneWidget);
    });

    testWidgets('a null onPressed disables it', (tester) async {
      await tester.pumpWidget(_host(const GradientButton(label: 'Go', onPressed: null)));

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    });
  });

  group('hero contrast (WCAG AA, 4.5:1)', () {
    for (final (name, gradients) in [('light', BrandGradients.light), ('dark', BrandGradients.dark)]) {
      test('white text passes on the deep and brand stops in $name', () {
        final colors = (gradients.heroGradient as LinearGradient).colors;
        // The brand text sits over the first two stops; the last one is covered by the sheet.
        // PT: O texto da marca fica sobre as duas primeiras paradas; a última é coberta pela folha.
        for (final stop in colors.take(2)) {
          expect(_contrast(gradients.onHero, stop), greaterThanOrEqualTo(4.5));
        }
      });
    }
  });
}

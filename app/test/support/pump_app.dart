import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Turns on the system "reduce motion" flag for the test: the aurora hero stands still, so `pumpAndSettle` ends.
/// PT: Liga a flag "reduzir movimento" do sistema no teste: o hero aurora fica parado, então `pumpAndSettle` termina.
void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Pumps [page] in a MaterialApp with the l10n delegates, under the [providers] given.
/// PT: Monta [page] num MaterialApp com os delegates de l10n, sob os [providers] informados.
Future<void> pumpApp(
  WidgetTester tester,
  Widget page, {
  List<SingleChildWidget> providers = const [],
}) {
  // A tall surface: the taller auth screens keep every button on screen (no scrolling needed).
  // PT: Uma superfície alta: as telas de auth, mais altas, mantêm todo botão visível (sem rolar).
  reduceMotion(tester);
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: page,
  );
  // MultiProvider asserts on an empty list: widgets that need no provider skip it.
  // PT: O MultiProvider falha com lista vazia: widgets que não precisam de provider o dispensam.
  return tester.pumpWidget(providers.isEmpty ? app : MultiProvider(providers: providers, child: app));
}

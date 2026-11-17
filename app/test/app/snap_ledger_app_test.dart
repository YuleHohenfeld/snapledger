import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/app/config_error_app.dart';
import 'package:snapledger/app/snap_ledger_app.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/features/auth/login/presentation/page/login_page.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../support/in_memory_secure_store.dart';
import '../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('builds its providers and opens the login when nothing is stored', (tester) async {
    reduceMotion(tester);
    final config = AppConfig.parse('https://api.test', isRelease: true);

    await tester.pumpWidget(SnapLedgerApp(config, secureStore: InMemorySecureStore()));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text(l10n.loginHeadline), findsWidgets);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).onGenerateTitle, isNotNull);
  });

  testWidgets('the config error screen explains the problem and offers no app', (tester) async {
    await tester.pumpWidget(const ConfigErrorApp());

    expect(find.text(l10n.configErrorTitle), findsOneWidget);
    expect(find.text(l10n.configErrorBody), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  test('a missing API_BASE_URL is refused, which main() turns into the config error screen', () {
    expect(
      () => AppConfig.parse('', isRelease: false),
      throwsA(isA<ConfigException>().having((e) => e.error, 'error', ConfigError.missing)),
    );
    expect(AppBrand.name, 'SnapLedger');
  });
}

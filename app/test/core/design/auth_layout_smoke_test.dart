import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/auth/login/presentation/page/login_page.dart';
import 'package:snapledger/features/auth/register/presentation/page/register_page.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_navigator.dart';
import '../../support/fake_session_refresher.dart';
import '../../support/pump_app.dart';

void main() {
  final pages = <String, Widget>{
    'login': const LoginPage(),
    'register': const RegisterPage(),
  };
  final themes = <String, ThemeData>{
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
  };

  for (final MapEntry(key: pageName, value: page) in pages.entries) {
    for (final MapEntry(key: themeName, value: theme) in themes.entries) {
      for (final keyboard in [0.0, 300.0]) {
        testWidgets(
          '$pageName renders in $themeName without overflow (keyboard $keyboard)',
          (tester) async {
            reduceMotion(tester);
            tester.view.physicalSize = const Size(360, 640);
            tester.view.devicePixelRatio = 1;
            tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
            addTearDown(tester.view.reset);
            final session = inMemorySession().session;
            final pending = PendingVerification(session: session);
            addTearDown(() {
              pending.dispose();
              session.dispose();
            });

            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  Provider<AuthRepository>.value(value: FakeAuthRepository()),
                  ChangeNotifierProvider<SessionNotifier>.value(value: session),
                  ChangeNotifierProvider<PendingVerification>.value(value: pending),
                  Provider<AppNavigator>.value(value: FakeNavigator()),
                ],
                child: MaterialApp(
                  theme: theme,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: page,
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.byType(FilledButton), findsOneWidget);
          },
        );
      }
    }
  }
}

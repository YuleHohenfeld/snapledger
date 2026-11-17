import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/otp_code_input.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/email_verification_repository.dart';
import 'package:snapledger/features/auth/password_reset/presentation/page/password_reset_page.dart';
import 'package:snapledger/features/auth/verify_email/presentation/page/verify_email_page.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_email_verification_repository.dart';
import '../../support/fake_navigator.dart';
import '../../support/fake_session_refresher.dart';
import '../../support/fake_user_repository.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final themes = <String, ThemeData>{'light': AppTheme.light(), 'dark': AppTheme.dark()};

  // Each case reaches a screen state through the UI, then checks nothing overflowed.
  // PT: Cada caso chega a um estado de tela pela UI, depois confere que nada estourou.
  final cases = <String, Future<void> Function(WidgetTester tester)>{
    'password reset, email step': (tester) async {},
    'password reset, code step': (tester) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.loginEmailLabel),
        'ana@example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, l10n.passwordResetSendCode));
      await tester.pumpAndSettle();
    },
    'password reset, new password step': (tester) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.loginEmailLabel),
        'ana@example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, l10n.passwordResetSendCode));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '042917');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
    },
    'password reset, done step': (tester) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.loginEmailLabel),
        'ana@example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, l10n.passwordResetSendCode));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '042917');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.passwordResetNewPasswordLabel),
        'fake-new-password',
      );
      await tester.tap(find.widgetWithText(FilledButton, l10n.passwordResetSubmit));
      await tester.pumpAndSettle();
    },
  };

  for (final MapEntry(key: name, value: reach) in cases.entries) {
    for (final MapEntry(key: themeName, value: theme) in themes.entries) {
      for (final keyboard in [0.0, 300.0]) {
        testWidgets('$name renders in $themeName without overflow (keyboard $keyboard)', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                Provider<AuthRepository>.value(value: FakeAuthRepository()),
                Provider<AppNavigator>.value(value: FakeNavigator()),
              ],
              child: MaterialApp(
                theme: theme,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const PasswordResetPage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          // The keyboard opens only after the step is reached, as it would for a real user.
          // PT: O teclado só abre depois de chegar ao passo, como para um usuário de verdade.
          await reach(tester);
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final MapEntry(key: themeName, value: theme) in themes.entries) {
    for (final keyboard in [0.0, 300.0]) {
      testWidgets('verify email renders in $themeName without overflow (keyboard $keyboard)', (
        tester,
      ) async {
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
              Provider<UserRepository>.value(value: FakeUserRepository()),
              Provider<EmailVerificationRepository>.value(
                value: FakeEmailVerificationRepository(),
              ),
              ChangeNotifierProvider<PendingVerification>.value(value: pending),
              Provider<AppNavigator>.value(value: FakeNavigator()),
            ],
            child: MaterialApp(
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const VerifyEmailPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(OtpCodeInput), findsOneWidget);
      });
    }
  }
}

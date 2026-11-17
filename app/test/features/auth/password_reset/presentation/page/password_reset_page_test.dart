import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/features/auth/password_reset/presentation/page/password_reset_page.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../../support/fake_auth_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeAuthRepository auth;
  late FakeNavigator navigator;

  setUp(() {
    auth = FakeAuthRepository();
    navigator = FakeNavigator();
  });

  Future<void> pumpReset(WidgetTester tester) => pumpApp(
    tester,
    const PasswordResetPage(),
    providers: [
      Provider<AuthRepository>.value(value: auth),
      Provider<AppNavigator>.value(value: navigator),
    ],
  );

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  String? errorUnder(WidgetTester tester, String label) => tester
      .widget<TextField>(find.descendant(of: field(label), matching: find.byType(TextField)))
      .decoration
      ?.errorText;

  Future<void> reachCodeStep(WidgetTester tester) async {
    await pumpReset(tester);
    await tester.enterText(field(l10n.loginEmailLabel), 'ana@example.com');
    await tester.tap(find.widgetWithText(FilledButton, l10n.passwordResetSendCode));
    await tester.pump();
    await tester.pump();
  }

  Future<void> submitCode(WidgetTester tester, {String code = '042917'}) async {
    await tester.enterText(field(l10n.codeFieldLabel), code);
    await tester.enterText(field(l10n.passwordResetNewPasswordLabel), 'fake-new-password');
    await tester.tap(find.widgetWithText(FilledButton, l10n.passwordResetSubmit));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the email step shows the title, the intro and the send button', (tester) async {
    await pumpReset(tester);

    expect(find.text(l10n.passwordResetTitle), findsOneWidget);
    expect(find.text(l10n.passwordResetEmailIntro), findsOneWidget);
    expect(find.widgetWithText(FilledButton, l10n.passwordResetSendCode), findsOneWidget);
    expect(field(l10n.codeFieldLabel), findsNothing);
  });

  testWidgets('an invalid email shows the field error and sends nothing', (tester) async {
    await pumpReset(tester);
    await tester.enterText(field(l10n.loginEmailLabel), 'not-an-email');

    await tester.tap(find.widgetWithText(FilledButton, l10n.passwordResetSendCode));
    await tester.pump();

    expect(errorUnder(tester, l10n.loginEmailLabel), l10n.validationEmailInvalid);
    expect(auth.resetRequests, isEmpty);
  });

  testWidgets('the code step shows the intro with the email, the fields and the cooldown', (
    tester,
  ) async {
    await reachCodeStep(tester);

    expect(find.text(l10n.passwordResetCodeIntro('ana@example.com')), findsOneWidget);
    expect(field(l10n.codeFieldLabel), findsOneWidget);
    expect(field(l10n.passwordResetNewPasswordLabel), findsOneWidget);
    expect(find.text(l10n.registerPasswordHelper(passwordMinBytes)), findsOneWidget);
    expect(find.text(l10n.codeResendIn('1:00')), findsOneWidget);
    expect(find.text(l10n.passwordResetSubmit), findsOneWidget);
  });

  testWidgets('use a different email goes back to the email step with the email prefilled', (
    tester,
  ) async {
    await reachCodeStep(tester);
    expect(find.widgetWithText(TextButton, l10n.passwordResetUseDifferentEmail), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, l10n.passwordResetUseDifferentEmail));
    await tester.pump();

    expect(find.text(l10n.passwordResetEmailIntro), findsOneWidget);
    expect(field(l10n.codeFieldLabel), findsNothing);
    final emailText = tester
        .widget<TextField>(find.descendant(of: field(l10n.loginEmailLabel), matching: find.byType(TextField)))
        .controller!
        .text;
    expect(emailText, 'ana@example.com');
  });

  testWidgets('the cooldown counts down on screen and re-enables the resend', (tester) async {
    await reachCodeStep(tester);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(l10n.codeResendIn('0:59')), findsOneWidget);

    await tester.pump(const Duration(seconds: 59));
    expect(find.text(l10n.codeResend), findsOneWidget);

    await tester.tap(find.text(l10n.codeResend));
    await tester.pump();
    await tester.pump();
    expect(auth.resetRequests, hasLength(2));
    expect(find.text(l10n.codeResendIn('1:00')), findsOneWidget);
  });

  testWidgets('a network failure on the first step stays there with a banner', (tester) async {
    auth.failure = const NetworkFailure();

    await reachCodeStep(tester);

    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(field(l10n.codeFieldLabel), findsNothing);
  });

  testWidgets('an invalid code shows under the code field and clears on edit', (tester) async {
    await reachCodeStep(tester);
    auth.failure = const ProblemFailure(status: 400, type: ProblemType.invalidCode);

    await submitCode(tester);

    expect(errorUnder(tester, l10n.codeFieldLabel), l10n.errorInvalidCode);
    expect(find.text(l10n.errorInvalidCode), findsOneWidget);

    await tester.enterText(field(l10n.codeFieldLabel), '04291');
    await tester.pump();

    expect(find.text(l10n.errorInvalidCode), findsNothing);
    expect(
      tester.widget<TextField>(find.descendant(of: field(l10n.codeFieldLabel), matching: find.byType(TextField))).controller!.text,
      '04291',
    );
  });

  testWidgets('a 429 shows the banner', (tester) async {
    await reachCodeStep(tester);
    auth.failure = const ProblemFailure(status: 429, type: ProblemType.tooManyRequests);

    await submitCode(tester);

    expect(find.text(l10n.errorTooManyRequests), findsOneWidget);
  });

  testWidgets('a short code shows the validation error and sends nothing', (tester) async {
    await reachCodeStep(tester);

    await submitCode(tester, code: '123');

    expect(errorUnder(tester, l10n.codeFieldLabel), l10n.validationCodeInvalid);
    expect(auth.resetConfirms, isEmpty);
  });

  testWidgets('the code field takes digits only, at most 6', (tester) async {
    await reachCodeStep(tester);

    await tester.enterText(field(l10n.codeFieldLabel), '12ab34567');

    final text = tester
        .widget<TextField>(find.descendant(of: field(l10n.codeFieldLabel), matching: find.byType(TextField)))
        .controller!
        .text;
    expect(text, '123456');
  });

  testWidgets('success shows the done message and back to sign in goes to the login', (
    tester,
  ) async {
    await reachCodeStep(tester);

    await submitCode(tester);

    expect(find.text(l10n.passwordResetDoneTitle), findsOneWidget);
    expect(find.text(l10n.passwordResetDoneBody), findsOneWidget);
    expect(field(l10n.codeFieldLabel), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, l10n.passwordResetBackToLogin));

    expect(navigator.wentTo, [AppRoute.login]);
  });

  testWidgets('back to sign in is available on the first step too', (tester) async {
    await pumpReset(tester);

    await tester.tap(find.widgetWithText(TextButton, l10n.passwordResetBackToLogin));

    expect(navigator.wentTo, [AppRoute.login]);
  });
}

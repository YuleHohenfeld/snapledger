import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/design/widgets/otp_code_input.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
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

  Finder sendButton() => find.widgetWithText(FilledButton, l10n.passwordResetSendCode);

  Finder confirmButton() => find.widgetWithText(FilledButton, l10n.passwordResetSubmit);

  OtpStatus otpStatus(WidgetTester tester) => tester.widget<OtpCodeInput>(find.byType(OtpCodeInput)).status;

  Future<void> reachCodeStep(WidgetTester tester) async {
    await pumpReset(tester);
    await tester.enterText(field(l10n.loginEmailLabel), 'ana@example.com');
    await tester.tap(sendButton());
    await tester.pump();
    await tester.pump();
  }

  Future<void> typeCode(WidgetTester tester, [String code = '042917']) async {
    await tester.enterText(find.byType(TextField), code);
    await tester.pump();
    await tester.pump();
  }

  Future<void> reachNewPasswordStep(WidgetTester tester) async {
    await reachCodeStep(tester);
    await typeCode(tester);
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('step 1 shows the headline, one line, the field and a back arrow', (tester) async {
    await pumpReset(tester);

    expect(find.text(l10n.passwordResetTitle), findsOneWidget);
    expect(find.text(l10n.passwordResetEmailIntro), findsOneWidget);
    expect(sendButton(), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(OtpCodeInput), findsNothing);
  });

  testWidgets('the back arrow of step 1 goes to the login', (tester) async {
    await pumpReset(tester);

    await tester.tap(find.byType(BackButton));

    expect(navigator.wentTo, [AppRoute.login]);
  });

  testWidgets('an invalid email shows the field error and sends nothing', (tester) async {
    await pumpReset(tester);
    await tester.enterText(field(l10n.loginEmailLabel), 'not-an-email');

    await tester.tap(sendButton());
    await tester.pump();

    expect(find.text(l10n.validationEmailInvalid), findsOneWidget);
    expect(auth.resetRequests, isEmpty);
  });

  testWidgets('a valid email moves to the code step showing the email in bold', (tester) async {
    await reachCodeStep(tester);

    expect(find.byType(OtpCodeInput), findsOneWidget);
    expect(find.text(l10n.codeVerificationTitle), findsOneWidget);
    final bold = tester.widgetList<RichText>(find.byType(RichText)).expand((r) {
      final spans = <TextSpan>[];
      r.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'ana@example.com') spans.add(span);
        return true;
      });
      return spans;
    });
    expect(bold.single.style?.fontWeight, FontWeight.w700);
    expect(auth.resetRequests.single.email, 'ana@example.com');
  });

  testWidgets('the code step announces the code input to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await reachCodeStep(tester);

    expect(find.bySemanticsLabel(RegExp('Verification code, 6 digits')), findsWidgets);
    handle.dispose();
  });

  testWidgets('the 6th digit verifies on its own, shows success, then opens the new password step', (
    tester,
  ) async {
    await reachCodeStep(tester);

    await typeCode(tester);

    expect(auth.resetVerifies.single.code, '042917');
    expect(otpStatus(tester), OtpStatus.success);
    expect(find.text(l10n.passwordResetNewPasswordTitle), findsNothing);

    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text(l10n.passwordResetNewPasswordTitle), findsOneWidget);
    expect(find.byType(OtpCodeInput), findsNothing);
  });

  testWidgets('a refused code turns the boxes red with the message, clears them and allows retyping', (
    tester,
  ) async {
    await reachCodeStep(tester);
    auth.verifyFailure = const ProblemFailure(status: 400, type: ProblemType.invalidCode);

    await typeCode(tester, '000000');
    await tester.pumpAndSettle();

    expect(otpStatus(tester), OtpStatus.error);
    expect(find.text(l10n.codeWrong), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);

    auth.verifyFailure = null;
    await typeCode(tester, '042917');
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text(l10n.passwordResetNewPasswordTitle), findsOneWidget);
  });

  testWidgets('a 429 on the code shows the too many attempts banner', (tester) async {
    await reachCodeStep(tester);
    auth.verifyFailure = const ProblemFailure(status: 429, type: ProblemType.tooManyRequests);

    await typeCode(tester);
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorTooManyRequests), findsOneWidget);
    expect(find.byType(OtpCodeInput), findsOneWidget);
  });

  testWidgets('the resend button waits for the cooldown, then sends another code', (tester) async {
    await reachCodeStep(tester);
    expect(find.text(l10n.codeResendIn('1:00')), findsOneWidget);

    await tester.pump(const Duration(seconds: 61));

    expect(find.text(l10n.codeResend), findsOneWidget);
    await tester.tap(find.text(l10n.codeResend));
    await tester.pump();
    await tester.pump();

    expect(auth.resetRequests, hasLength(2));
    expect(find.text(l10n.codeResendIn('1:00')), findsOneWidget);
  });

  testWidgets('the back arrow of step 2 returns to the email step keeping the email', (tester) async {
    await reachCodeStep(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pump();

    expect(sendButton(), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'ana@example.com'), findsOneWidget);
  });

  testWidgets('step 3 shows a live checklist that turns green as the password grows', (tester) async {
    await reachNewPasswordStep(tester);
    final requirement = find.text(l10n.passwordRequirementMinLength(8));
    Color? colorOf() => tester.widget<Text>(requirement).style?.color;
    final before = colorOf();

    await tester.enterText(field(l10n.passwordResetNewPasswordLabel), 'fake-new-password');
    await tester.pump();

    expect(colorOf(), isNot(before));
  });

  testWidgets('a weak password shows the field error and confirms nothing', (tester) async {
    await reachNewPasswordStep(tester);
    await tester.enterText(field(l10n.passwordResetNewPasswordLabel), 'short');

    await tester.tap(confirmButton());
    await tester.pump();

    expect(find.text(l10n.validationPasswordTooShort(8)), findsOneWidget);
    expect(auth.resetConfirms, isEmpty);
  });

  testWidgets('confirming sends the token and shows the success screen, then goes to the login', (
    tester,
  ) async {
    await reachNewPasswordStep(tester);
    await tester.enterText(field(l10n.passwordResetNewPasswordLabel), 'fake-new-password');

    await tester.tap(confirmButton());
    await tester.pump();
    await tester.pump();

    expect(auth.resetConfirms.single.resetToken, 'fake-reset-token');
    expect(find.text(l10n.passwordResetDoneTitle), findsOneWidget);
    expect(find.text(l10n.passwordResetDoneBody), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(find.text(l10n.passwordResetBackToLogin));
    expect(navigator.wentTo, [AppRoute.login]);
  });

  testWidgets('an expired reset session returns to the email step with the message', (tester) async {
    await reachNewPasswordStep(tester);
    auth.confirmFailure = const ProblemFailure(status: 400, type: ProblemType.invalidResetToken);
    await tester.enterText(field(l10n.passwordResetNewPasswordLabel), 'fake-new-password');

    await tester.tap(confirmButton());
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.errorResetSessionExpired), findsOneWidget);
    expect(sendButton(), findsOneWidget);
  });

  testWidgets('a 429 on the new password shows the banner and keeps the step', (tester) async {
    await reachNewPasswordStep(tester);
    auth.confirmFailure = const ProblemFailure(status: 429, type: ProblemType.tooManyRequests);
    await tester.enterText(field(l10n.passwordResetNewPasswordLabel), 'fake-new-password');

    await tester.tap(confirmButton());
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.errorTooManyRequests), findsOneWidget);
    expect(confirmButton(), findsOneWidget);
  });
}

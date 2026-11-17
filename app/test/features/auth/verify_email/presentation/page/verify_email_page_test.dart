import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/design/widgets/otp_code_input.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/email_verification_repository.dart';
import 'package:snapledger/features/auth/verify_email/presentation/page/verify_email_page.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../../support/fake_email_verification_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/fake_user_repository.dart';
import '../../../../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeUserRepository users;
  late FakeEmailVerificationRepository verification;
  late FakeNavigator navigator;
  late SessionNotifier session;
  late PendingVerification pending;

  setUp(() {
    users = FakeUserRepository();
    verification = FakeEmailVerificationRepository();
    navigator = FakeNavigator();
    session = inMemorySession().session;
    pending = PendingVerification(session: session);
  });

  tearDown(() {
    pending.dispose();
    session.dispose();
  });

  Future<void> pumpVerify(WidgetTester tester) async {
    await pumpApp(
      tester,
      const VerifyEmailPage(),
      providers: [
        Provider<UserRepository>.value(value: users),
        Provider<EmailVerificationRepository>.value(value: verification),
        ChangeNotifierProvider<PendingVerification>.value(value: pending),
        Provider<AppNavigator>.value(value: navigator),
      ],
    );
    await tester.pump();
    await tester.pump();
  }

  Finder codeInput() => find.byType(TextField);

  OtpStatus otpStatus(WidgetTester tester) =>
      tester.widget<OtpCodeInput>(find.byType(OtpCodeInput)).status;

  Future<void> typeCode(WidgetTester tester, String code) async {
    await tester.enterText(codeInput(), code);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the check your email screen with the address, boxes and resend line', (
    tester,
  ) async {
    await pumpVerify(tester);

    expect(find.text(l10n.codeVerificationTitle), findsOneWidget);
    expect(find.textContaining('ana@example.com', findRichText: true), findsOneWidget);
    expect(find.byType(OtpCodeInput), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text(l10n.codeResendIn('1:00')), findsOneWidget);
  });

  testWidgets('after register the footer says Skip for now', (tester) async {
    pending.begin();
    await pumpVerify(tester);

    expect(find.text(l10n.verifyEmailSkip), findsOneWidget);
  });

  testWidgets('opened from the profile there is no skip text and the arrow pops', (tester) async {
    await pumpVerify(tester);

    expect(find.text(l10n.verifyEmailSkip), findsNothing);
    await tester.tap(find.byType(BackButton));

    expect(navigator.pops, 1);
    expect(navigator.wentTo, isEmpty);
  });

  testWidgets('opened from the profile, a code is sent right away', (tester) async {
    await pumpVerify(tester);
    expect(verification.sends, 1);
  });

  testWidgets('after register no code is sent on open', (tester) async {
    pending.begin();

    await pumpVerify(tester);

    expect(verification.sends, 0);
    expect(find.text(l10n.codeResendIn('1:00')), findsOneWidget);
  });

  testWidgets('a valid code turns green, then leaves by itself (profile: pop)', (tester) async {
    await pumpVerify(tester);

    await typeCode(tester, '042917');

    expect(verification.confirms, ['042917']);
    expect(otpStatus(tester), OtpStatus.success);
    expect(navigator.pops, 0);

    await tester.pump(const Duration(milliseconds: 700));

    expect(navigator.pops, 1);
  });

  testWidgets('a valid code after register leaves to the summary and clears the flag', (tester) async {
    pending.begin();
    await pumpVerify(tester);

    await typeCode(tester, '042917');
    await tester.pump(const Duration(milliseconds: 700));

    expect(navigator.wentTo, [AppRoute.summary]);
    expect(pending.isPending, isFalse);
  });

  testWidgets('a wrong code turns red with the message, clears the boxes and keeps the flag', (
    tester,
  ) async {
    pending.begin();
    await pumpVerify(tester);
    verification.confirmFailure = const ProblemFailure(
      status: 400,
      type: ProblemType.invalidCode,
    );

    await typeCode(tester, '000000');
    await tester.pumpAndSettle();

    expect(otpStatus(tester), OtpStatus.error);
    expect(find.text(l10n.codeWrong), findsOneWidget);
    expect(tester.widget<TextField>(codeInput()).controller!.text, isEmpty);
    expect(pending.isPending, isTrue);

    await tester.enterText(codeInput(), '0');
    await tester.pump();

    expect(otpStatus(tester), OtpStatus.idle);
    expect(find.text(l10n.codeWrong), findsNothing);
  });

  testWidgets('an already verified account shows the success message and Continue leaves', (
    tester,
  ) async {
    users.emailVerified = true;
    await pumpVerify(tester);

    expect(find.text(l10n.verifyEmailSuccess), findsOneWidget);
    await tester.tap(find.text(l10n.verifyEmailContinue));

    expect(navigator.pops, 1);
  });

  testWidgets('a 429 on the automatic send shows the banner', (tester) async {
    verification.sendFailure = const ProblemFailure(
      status: 429,
      type: ProblemType.tooManyRequests,
    );

    await pumpVerify(tester);

    expect(find.text(l10n.errorTooManyRequests), findsOneWidget);
  });

  testWidgets('skip after register clears the flag and goes to the summary', (tester) async {
    pending.begin();
    await pumpVerify(tester);

    await tester.tap(find.text(l10n.verifyEmailSkip));

    expect(pending.isPending, isFalse);
    expect(navigator.wentTo, [AppRoute.summary]);
  });

  testWidgets('a load failure offers a retry', (tester) async {
    users.failure = const NetworkFailure();
    await pumpVerify(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    users.failure = null;
    await tester.tap(find.text(l10n.profileRetry));
    await tester.pump();
    await tester.pump();

    expect(find.byType(OtpCodeInput), findsOneWidget);
  });
}

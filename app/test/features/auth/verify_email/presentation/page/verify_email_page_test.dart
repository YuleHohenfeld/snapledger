import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/api/api_failure.dart';
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

  Finder codeField() => find.widgetWithText(TextFormField, l10n.codeFieldLabel);

  testWidgets('shows who the code was sent to, the field and the buttons', (tester) async {
    await pumpVerify(tester);

    expect(find.text(l10n.verifyEmailIntro('ana@example.com')), findsOneWidget);
    expect(codeField(), findsOneWidget);
    expect(find.widgetWithText(FilledButton, l10n.verifyEmailSubmit), findsOneWidget);
    expect(find.text(l10n.verifyEmailBack), findsOneWidget);
    expect(find.text(l10n.codeResendIn('1:00')), findsOneWidget);
  });

  testWidgets('after register the secondary button says Skip for now', (tester) async {
    pending.begin();
    await pumpVerify(tester);

    expect(find.text(l10n.verifyEmailSkip), findsOneWidget);
    expect(find.text(l10n.verifyEmailBack), findsNothing);
  });

  testWidgets('opened from the profile the secondary button says Back and pops', (tester) async {
    await pumpVerify(tester);

    expect(find.text(l10n.verifyEmailSkip), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, l10n.verifyEmailBack));

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

  testWidgets('a valid code verifies and Continue leaves', (tester) async {
    await pumpVerify(tester);

    await tester.enterText(codeField(), '042917');
    await tester.tap(find.widgetWithText(FilledButton, l10n.verifyEmailSubmit));
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.verifyEmailSuccess), findsOneWidget);

    await tester.tap(find.text(l10n.verifyEmailContinue));
    expect(navigator.pops, 1);
  });

  testWidgets('an invalid code shows under the field and clears on edit', (tester) async {
    await pumpVerify(tester);
    verification.confirmFailure = const ProblemFailure(
      status: 400,
      type: ProblemType.invalidCode,
    );

    await tester.enterText(codeField(), '000000');
    await tester.tap(find.widgetWithText(FilledButton, l10n.verifyEmailSubmit));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.errorInvalidCode), findsOneWidget);

    await tester.enterText(codeField(), '00000');
    await tester.pump();

    expect(find.text(l10n.errorInvalidCode), findsNothing);
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

    expect(find.text(l10n.verifyEmailIntro('ana@example.com')), findsOneWidget);
  });
}

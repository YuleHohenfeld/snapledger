import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/features/auth/register/presentation/page/register_page.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../../support/fake_auth_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeAuthRepository auth;
  late SessionNotifier session;
  late PendingVerification pending;
  late FakeNavigator navigator;

  setUp(() {
    auth = FakeAuthRepository();
    session = inMemorySession().session;
    pending = PendingVerification(session: session);
    navigator = FakeNavigator();
  });

  tearDown(() {
    pending.dispose();
    session.dispose();
  });

  Future<void> pumpRegister(WidgetTester tester) => pumpApp(
    tester,
    const RegisterPage(),
    providers: [
      Provider<AuthRepository>.value(value: auth),
      ChangeNotifierProvider<SessionNotifier>.value(value: session),
      ChangeNotifierProvider<PendingVerification>.value(value: pending),
      Provider<AppNavigator>.value(value: navigator),
    ],
  );

  Finder field(String label) => find.widgetWithText(TextFormField, label);
  Finder submitButton() => find.widgetWithText(FilledButton, l10n.registerSubmit);

  /// The error text shown under the field labeled [label], or null.
  /// PT: O texto de erro exibido sob o campo com rótulo [label], ou null.
  String? errorUnder(WidgetTester tester, String label) => tester
      .widget<TextField>(find.descendant(of: field(label), matching: find.byType(TextField)))
      .decoration
      ?.errorText;

  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.enterText(field(l10n.registerNameLabel), 'Ana Souza');
    await tester.enterText(field(l10n.registerEmailLabel), 'ana@example.com');
    await tester.enterText(field(l10n.registerPasswordLabel), 'fake-password');
    await tester.tap(submitButton());
    await tester.pump();
  }

  testWidgets('shows the localized title, labels, helper and buttons', (tester) async {
    await pumpRegister(tester);

    expect(find.text(AppBrand.name), findsOneWidget);
    expect(find.text(l10n.registerHeadline), findsOneWidget);
    expect(find.text(l10n.registerSubtitle), findsOneWidget);
    expect(find.text(l10n.registerHaveAccountPrompt), findsOneWidget);
    expect(field(l10n.registerNameLabel), findsOneWidget);
    expect(field(l10n.registerEmailLabel), findsOneWidget);
    expect(field(l10n.registerPasswordLabel), findsOneWidget);
    expect(find.text(l10n.registerPasswordHelper(passwordMinBytes)), findsOneWidget);
    expect(submitButton(), findsOneWidget);
    expect(find.text(l10n.registerHaveAccount), findsOneWidget);
  });

  testWidgets('shows client errors under the fields and sends nothing', (tester) async {
    await pumpRegister(tester);
    await tester.enterText(field(l10n.registerNameLabel), 'a' * 81);
    await tester.enterText(field(l10n.registerEmailLabel), 'josé@example.com');
    await tester.enterText(field(l10n.registerPasswordLabel), 'short');

    await tester.tap(submitButton());
    await tester.pump();

    expect(find.text(l10n.validationNameTooLong(nameMaxCodePoints)), findsOneWidget);
    expect(find.text(l10n.validationEmailInvalid), findsOneWidget);
    expect(find.text(l10n.validationPasswordTooShort(passwordMinBytes)), findsOneWidget);
    expect(auth.registers, isEmpty);
  });

  testWidgets('editing a field hides only its error; submitting checks again', (tester) async {
    await pumpRegister(tester);
    await tester.tap(submitButton());
    await tester.pump();
    expect(find.text(l10n.validationRequired), findsNWidgets(3));

    await tester.enterText(field(l10n.registerNameLabel), 'A');
    await tester.pump();

    expect(errorUnder(tester, l10n.registerNameLabel), isNull);
    expect(errorUnder(tester, l10n.registerEmailLabel), l10n.validationRequired);
    expect(errorUnder(tester, l10n.registerPasswordLabel), l10n.validationRequired);
    expect(find.text('A'), findsOneWidget);

    await tester.enterText(field(l10n.registerEmailLabel), 'x');
    await tester.tap(submitButton());
    await tester.pump();

    expect(errorUnder(tester, l10n.registerNameLabel), isNull);
    expect(errorUnder(tester, l10n.registerEmailLabel), l10n.validationEmailInvalid);
    expect(errorUnder(tester, l10n.registerPasswordLabel), l10n.validationRequired);
  });

  testWidgets('the button is busy while the request is in flight', (tester) async {
    auth.gate = Completer<void>();
    await pumpRegister(tester);

    await fillAndSubmit(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    auth.gate!.complete();
    await tester.pump();

    expect(auth.registers, hasLength(1));
    expect(session.status, SessionStatus.signedIn);
    // Still busy after success: the router (not this screen) leaves the page.
    // PT: Continua ocupado após o sucesso: o router (não esta tela) sai da página.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('editing the email removes the taken-email error', (tester) async {
    auth.failure = const ProblemFailure(status: 409, type: ProblemType.emailAlreadyRegistered);
    await pumpRegister(tester);
    await fillAndSubmit(tester);
    await tester.pumpAndSettle();
    expect(errorUnder(tester, l10n.registerEmailLabel), l10n.errorEmailTaken);

    await tester.enterText(field(l10n.registerEmailLabel), 'bia@example.com');
    await tester.pump();

    expect(errorUnder(tester, l10n.registerEmailLabel), isNull);
  });

  testWidgets('a taken email shows under the email field, with no banner', (tester) async {
    auth.failure = const ProblemFailure(status: 409, type: ProblemType.emailAlreadyRegistered);
    await pumpRegister(tester);

    await fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(errorUnder(tester, l10n.registerEmailLabel), l10n.errorEmailTaken);
    expect(find.text(l10n.errorEmailTaken), findsOneWidget);
    expect(errorUnder(tester, l10n.registerNameLabel), isNull);
  });

  testWidgets('server field errors go under the matching fields, with no banner', (tester) async {
    auth.failure = const ProblemFailure(
      status: 400,
      type: ProblemType.validationError,
      fieldErrors: ['name', 'password'],
    );
    await pumpRegister(tester);

    await fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(errorUnder(tester, l10n.registerNameLabel), l10n.validationFieldInvalid);
    expect(errorUnder(tester, l10n.registerEmailLabel), isNull);
    expect(errorUnder(tester, l10n.registerPasswordLabel), l10n.validationFieldInvalid);
    expect(find.text(l10n.errorValidation), findsNothing);
  });

  testWidgets('a field the form does not have falls back to the banner', (tester) async {
    auth.failure = const ProblemFailure(
      status: 400,
      type: ProblemType.validationError,
      fieldErrors: ['currency'],
    );
    await pumpRegister(tester);

    await fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorValidation), findsOneWidget);
  });

  testWidgets('other failures show in the banner', (tester) async {
    auth.failure = const ProblemFailure(
      status: 500,
      type: ProblemType.internalError,
      errorId: '3f9a1c2e',
    );
    await pumpRegister(tester);

    await fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorUnexpectedWithId('3f9a1c2e')), findsOneWidget);
  });

  testWidgets('the password is hidden by default and the eye button toggles it', (tester) async {
    await pumpRegister(tester);

    TextField passwordInput() => tester.widget<TextField>(
      find.descendant(of: field(l10n.registerPasswordLabel), matching: find.byType(TextField)),
    );

    expect(passwordInput().obscureText, isTrue);
    expect(passwordInput().autofillHints, [AutofillHints.newPassword]);

    await tester.tap(find.byTooltip(l10n.passwordShow));
    await tester.pump();

    expect(passwordInput().obscureText, isFalse);
  });

  testWidgets('"I already have an account" asks the navigator for the login route', (tester) async {
    await pumpRegister(tester);

    await tester.ensureVisible(find.text(l10n.registerHaveAccount));
    await tester.tap(find.text(l10n.registerHaveAccount));

    expect(navigator.wentTo, [AppRoute.login]);
  });
}

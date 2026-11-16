import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/storage/secure_store.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/auth/login/presentation/page/login_page.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../../support/fake_auth_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeAuthRepository auth;
  late SessionNotifier session;
  late FakeNavigator navigator;

  setUp(() {
    auth = FakeAuthRepository();
    session = inMemorySession().session;
    navigator = FakeNavigator();
  });

  tearDown(() => session.dispose());

  Future<void> pumpLogin(WidgetTester tester) => pumpApp(
    tester,
    const LoginPage(),
    providers: [
      Provider<AuthRepository>.value(value: auth),
      ChangeNotifierProvider<SessionNotifier>.value(value: session),
      Provider<AppNavigator>.value(value: navigator),
    ],
  );

  Finder field(String label) => find.widgetWithText(TextFormField, label);
  Finder submitButton() => find.widgetWithText(FilledButton, l10n.loginSubmit);

  Future<void> fillAndSubmit(WidgetTester tester, {String email = 'ana@example.com'}) async {
    await tester.enterText(field(l10n.loginEmailLabel), email);
    await tester.enterText(field(l10n.loginPasswordLabel), 'fake-password');
    await tester.tap(submitButton());
    await tester.pump();
  }

  testWidgets('shows the localized title, labels and buttons', (tester) async {
    await pumpLogin(tester);

    expect(find.text(AppBrand.name), findsOneWidget);
    expect(find.text(l10n.brandTagline), findsOneWidget);
    expect(find.text(l10n.loginHeadline), findsOneWidget);
    expect(find.text(l10n.loginSubtitle), findsOneWidget);
    expect(find.text(l10n.loginNoAccount), findsOneWidget);
    expect(field(l10n.loginEmailLabel), findsOneWidget);
    expect(field(l10n.loginPasswordLabel), findsOneWidget);
    expect(submitButton(), findsOneWidget);
    expect(find.text(l10n.loginCreateAccount), findsOneWidget);
  });

  testWidgets('shows client errors under the fields and sends nothing', (tester) async {
    await pumpLogin(tester);

    await tester.tap(submitButton());
    await tester.pump();

    expect(find.text(l10n.validationRequired), findsNWidgets(2));
    expect(auth.logins, isEmpty);

    await tester.enterText(field(l10n.loginEmailLabel), 'ana @example.com');
    await tester.tap(submitButton());
    await tester.pump();

    expect(find.text(l10n.validationEmailInvalid), findsOneWidget);
    expect(auth.logins, isEmpty);
  });

  String? errorUnder(WidgetTester tester, String label) => tester
      .widget<TextField>(find.descendant(of: field(label), matching: find.byType(TextField)))
      .decoration
      ?.errorText;

  testWidgets('editing a field hides only its error; submitting checks again', (tester) async {
    await pumpLogin(tester);
    await tester.tap(submitButton());
    await tester.pump();
    expect(find.text(l10n.validationRequired), findsNWidgets(2));

    await tester.enterText(field(l10n.loginEmailLabel), 'a');
    await tester.pump();

    expect(errorUnder(tester, l10n.loginEmailLabel), isNull);
    expect(errorUnder(tester, l10n.loginPasswordLabel), l10n.validationRequired);
    // The text stays: only the message goes away.
    // PT: O texto fica: só a mensagem some.
    expect(find.text('a'), findsOneWidget);

    await tester.tap(submitButton());
    await tester.pump();

    expect(errorUnder(tester, l10n.loginEmailLabel), l10n.validationEmailInvalid);
    expect(errorUnder(tester, l10n.loginPasswordLabel), l10n.validationRequired);
  });

  testWidgets('editing the email removes the server field error', (tester) async {
    auth.failure = const ProblemFailure(
      status: 400,
      type: ProblemType.validationError,
      fieldErrors: ['email'],
    );
    await pumpLogin(tester);
    await fillAndSubmit(tester);
    await tester.pumpAndSettle();
    expect(errorUnder(tester, l10n.loginEmailLabel), l10n.validationFieldInvalid);

    await tester.enterText(field(l10n.loginEmailLabel), 'ana@example.org');
    await tester.pump();

    expect(errorUnder(tester, l10n.loginEmailLabel), isNull);
  });

  testWidgets('the button is busy while the request is in flight', (tester) async {
    auth.gate = Completer<void>();
    await pumpLogin(tester);

    await fillAndSubmit(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.tap(find.byType(FilledButton));
    auth.gate!.complete();
    await tester.pump();

    expect(auth.logins, hasLength(1));
    expect(session.status, SessionStatus.signedIn);
    // Still busy after success: the router (not this screen) leaves the page.
    // PT: Continua ocupado após o sucesso: o router (não esta tela) sai da página.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('invalid credentials show in the banner, not under a field', (tester) async {
    auth.failure = const ProblemFailure(status: 401, type: ProblemType.invalidCredentials);
    await pumpLogin(tester);

    await fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorInvalidCredentials), findsOneWidget);
    expect(find.text(l10n.validationFieldInvalid), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });

  testWidgets('network and storage failures show in the banner', (tester) async {
    auth.failure = const NetworkFailure();
    await pumpLogin(tester);
    await fillAndSubmit(tester);
    await tester.pumpAndSettle();
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    auth.failure = const SecureStoreException('write');
    await tester.tap(submitButton());
    await tester.pumpAndSettle();
    expect(find.text(l10n.errorStorage), findsOneWidget);
  });

  testWidgets('server field errors show under the matching field, with no banner', (tester) async {
    auth.failure = const ProblemFailure(
      status: 400,
      type: ProblemType.validationError,
      fieldErrors: ['email'],
    );
    await pumpLogin(tester);

    await fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text(l10n.validationFieldInvalid), findsOneWidget);
    expect(find.text(l10n.errorValidation), findsNothing);
  });

  testWidgets('the password is hidden by default and the eye button toggles it', (tester) async {
    await pumpLogin(tester);

    TextField passwordInput() => tester.widget<TextField>(
      find.descendant(of: field(l10n.loginPasswordLabel), matching: find.byType(TextField)),
    );

    expect(passwordInput().obscureText, isTrue);
    expect(passwordInput().autocorrect, isFalse);
    expect(passwordInput().enableSuggestions, isFalse);

    await tester.tap(find.byTooltip(l10n.passwordShow));
    await tester.pump();
    expect(passwordInput().obscureText, isFalse);

    await tester.tap(find.byTooltip(l10n.passwordHide));
    await tester.pump();
    expect(passwordInput().obscureText, isTrue);
  });

  testWidgets('"create account" asks the navigator for the register route', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text(l10n.loginCreateAccount));

    expect(navigator.wentTo, [AppRoute.register]);
  });
}

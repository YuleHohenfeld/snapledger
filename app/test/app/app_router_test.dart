import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/app/app_routes.dart';
import 'package:snapledger/core/design/widgets/otp_code_input.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/router/app_router.dart';
import 'package:snapledger/core/router/go_router_navigator.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/email_verification_repository.dart';
import 'package:snapledger/features/auth/login/presentation/page/login_page.dart';
import 'package:snapledger/features/auth/password_reset/presentation/page/password_reset_page.dart';
import 'package:snapledger/features/auth/splash/presentation/page/splash_page.dart';
import 'package:snapledger/features/auth/verify_email/presentation/page/verify_email_page.dart';
import 'package:snapledger/features/categories/_shared/data/repositories/category_repository.dart';
import 'package:snapledger/features/categories/manage/presentation/page/category_manage_page.dart';
import 'package:snapledger/features/expenses/_shared/data/repositories/expense_repository.dart';
import 'package:snapledger/features/expenses/form/presentation/page/expense_form_page.dart';
import 'package:snapledger/features/expenses/list/presentation/page/expense_list_page.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_category_repository.dart';
import '../support/fake_email_verification_repository.dart';
import '../support/fake_expense_repository.dart';
import '../support/fake_session_refresher.dart';
import '../support/fake_user_repository.dart';
import '../support/in_memory_secure_store.dart';
import '../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeSessionRefresher refresher;
  late SessionNotifier session;
  late FakeAuthRepository auth;
  late FakeEmailVerificationRepository verification;
  late PendingVerification pending;
  late FakeExpenseRepository expenses;
  late GoRouter router;

  setUp(() {
    expenses = FakeExpenseRepository(expenses: [fakeExpense(id: 'e1')]);
    refresher = FakeSessionRefresher(() async => const SessionEnded());
    session = SessionNotifier(tokens: TokenStore(InMemorySecureStore()), refresher: refresher);
    auth = FakeAuthRepository();
    verification = FakeEmailVerificationRepository();
    pending = PendingVerification(session: session);
    router = buildRouter(session, pending, appRoutes);
  });

  tearDown(() {
    router.dispose();
    pending.dispose();
    session.dispose();
  });

  // A tall surface: the auth forms keep every button on screen.
  // PT: Uma superfície alta: os formulários de auth mantêm todo botão visível.
  Future<void> pumpRouter(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1400);
    reduceMotion(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionNotifier>.value(value: session),
          Provider<AuthRepository>.value(value: auth),
          Provider<EmailVerificationRepository>.value(value: verification),
          ChangeNotifierProvider<PendingVerification>.value(value: pending),
          Provider<UserRepository>.value(value: FakeUserRepository()),
          Provider<CategoryRepository>.value(value: FakeCategoryRepository()),
          Provider<ExpenseRepository>.value(value: expenses),
          Provider<AppNavigator>.value(value: GoRouterNavigator(router)),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
  }

  String location() => router.routeInformationProvider.value.uri.toString();

  testWidgets('starts on the splash while the session is unknown', (tester) async {
    final gate = Completer<RefreshOutcome>();
    refresher.onRefresh = () => gate.future;

    await pumpRouter(tester);

    expect(find.byType(SplashPage), findsOneWidget);
    expect(location(), '/splash');
    gate.complete(const SessionEnded());
    await tester.pumpAndSettle();
  });

  testWidgets('a stored session opens the shell with the three tabs', (tester) async {
    refresher.onRefresh = () async => const Refreshed('fake-access-1');

    await pumpRouter(tester);
    await tester.pumpAndSettle();

    expect(location(), '/summary');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(l10n.navSummary), findsWidgets);
    expect(find.text(l10n.navExpenses), findsOneWidget);
    expect(find.text(l10n.navProfile), findsOneWidget);
  });

  testWidgets('go(AppRoute.categories.path) opens the category management page', (tester) async {
    refresher.onRefresh = () async => const Refreshed('fake-access-1');
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    router.go(AppRoute.categories.path);
    await tester.pumpAndSettle();

    expect(location(), AppRoute.categories.path);
    expect(find.byType(CategoryManagePage), findsOneWidget);
  });

  testWidgets('no stored session opens the login', (tester) async {
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(location(), '/login');
  });

  testWidgets('a successful login leaves the login screen', (tester) async {
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.loginEmailLabel),
      'ana@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.loginPasswordLabel),
      'fake-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n.loginSubmit));
    await tester.pumpAndSettle();

    expect(session.status, SessionStatus.signedIn);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(location(), '/summary');
  });

  testWidgets('a login after a stale pending flag goes to the summary, not the verification', (
    tester,
  ) async {
    pending.begin();
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.loginEmailLabel),
      'ana@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.loginPasswordLabel),
      'fake-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n.loginSubmit));
    await tester.pumpAndSettle();

    expect(location(), '/summary');
    expect(pending.isPending, isFalse);
  });

  testWidgets('wiping the session sends the user back to login', (tester) async {
    refresher.onRefresh = () async => const Refreshed('fake-access-1');
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    await session.wipe();
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('each tab keeps its page alive when another tab is selected', (tester) async {
    refresher.onRefresh = () async => const Refreshed('fake-access-1');
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.navExpenses));
    await tester.pumpAndSettle();
    expect(location(), '/expenses');
    expect(find.byType(ExpenseListPage), findsOneWidget);

    await tester.tap(find.text(l10n.navSummary).last);
    await tester.pumpAndSettle();

    expect(location(), '/summary');
    expect(find.byType(ExpenseListPage, skipOffstage: false), findsOneWidget);
  });

  testWidgets('/expenses/new opens the empty form above the list', (tester) async {
    refresher.onRefresh = () async => const Refreshed('fake-access-1');
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    router.go(AppRoute.expenseNew.path);
    await tester.pumpAndSettle();

    expect(location(), '/expenses/new');
    expect(find.byType(ExpenseFormPage), findsOneWidget);
    expect(find.text(l10n.expenseFormNewTitle), findsOneWidget);
    expect(find.byType(ExpenseListPage, skipOffstage: false), findsOneWidget);
  });

  testWidgets('/expenses/:id opens that expense for editing, loaded by id', (tester) async {
    refresher.onRefresh = () async => const Refreshed('fake-access-1');
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    router.go(AppRoute.expenseEditPath('e1'));
    await tester.pumpAndSettle();

    expect(location(), '/expenses/e1');
    expect(find.text(l10n.expenseFormEditTitle), findsOneWidget);
    expect(find.text('Weekly groceries'), findsOneWidget);
    expect(expenses.fetched, ['e1']);
  });

  testWidgets('/expenses/:id for an unknown id shows not found', (tester) async {
    refresher.onRefresh = () async => const Refreshed('fake-access-1');
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    router.go(AppRoute.expenseEditPath('missing'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.expenseFormNotFoundTitle), findsOneWidget);
  });

  testWidgets('the navigator pushes the edit screen with the id encoded, and pop returns to the list', (
    tester,
  ) async {
    refresher.onRefresh = () async => const Refreshed('fake-access-1');
    await pumpRouter(tester);
    await tester.pumpAndSettle();
    router.go(AppRoute.expenses.path);
    await tester.pumpAndSettle();

    unawaited(GoRouterNavigator(router).pushExpenseEdit('a/b'));
    await tester.pumpAndSettle();
    // The id went out as one encoded segment and came back decoded, so the form asked for 'a/b'.
    // PT: O id saiu como um só segmento codificado e voltou decodificado, então o formulário pediu 'a/b'.
    expect(find.byType(ExpenseFormPage), findsOneWidget);
    expect(expenses.fetched, ['a/b']);

    GoRouterNavigator(router).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseFormPage), findsNothing);
    expect(find.byType(ExpenseListPage), findsOneWidget);
  });

  testWidgets('a deep link to an expense does not survive login (only tab roots are allowlisted)', (
    tester,
  ) async {
    router.go(AppRoute.expenseEditPath('e1'));
    await pumpRouter(tester);
    await tester.pumpAndSettle();
    expect(location(), '/login');

    await session.signIn(auth.response.tokens);
    await tester.pumpAndSettle();

    expect(location(), '/summary');
  });

  testWidgets('a deep link to a tab survives login through from', (tester) async {
    router.go('/expenses');
    await pumpRouter(tester);
    await tester.pumpAndSettle();
    expect(location(), '/login?from=%2Fexpenses');

    await session.signIn(auth.response.tokens);
    await tester.pumpAndSettle();

    expect(location(), '/expenses');
  });

  Future<void> registerFromTheForm(WidgetTester tester) async {
    await pumpRouter(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.loginCreateAccount));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, l10n.registerNameLabel), 'Ana Souza');
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.registerEmailLabel),
      'ana@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.registerPasswordLabel),
      'fake-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n.registerSubmit));
    await tester.pumpAndSettle();
  }

  testWidgets('a successful register opens the verify email screen without sending a code', (
    tester,
  ) async {
    await registerFromTheForm(tester);

    expect(location(), '/verify-email');
    expect(find.byType(VerifyEmailPage), findsOneWidget);
    expect(find.byType(OtpCodeInput), findsOneWidget);
    expect(verification.sends, 0);
  });

  testWidgets('skipping the verification after register goes to the summary', (tester) async {
    await registerFromTheForm(tester);

    await tester.tap(find.text(l10n.verifyEmailSkip));
    await tester.pumpAndSettle();

    expect(location(), '/summary');
    expect(pending.isPending, isFalse);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a signed out user cannot open the verify email screen', (tester) async {
    router.go('/verify-email');
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    expect(find.byType(VerifyEmailPage), findsNothing);
    expect(location(), '/login');
  });

  testWidgets('a signed in user opening the forgot password screen lands on the summary', (
    tester,
  ) async {
    refresher.onRefresh = () async => const Refreshed('fake-access-1');
    router.go('/forgot-password');
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    expect(find.byType(PasswordResetPage), findsNothing);
    expect(location(), '/summary');
  });

  testWidgets('a signed out user reaches the forgot password screen from the login', (
    tester,
  ) async {
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.loginForgotPassword));
    await tester.pumpAndSettle();

    expect(location(), '/forgot-password');
    expect(find.byType(PasswordResetPage), findsOneWidget);
  });

  testWidgets('the navigator intents move the router', (tester) async {
    await pumpRouter(tester);
    await tester.pumpAndSettle();

    GoRouterNavigator(router).goTo(AppRoute.register);
    await tester.pumpAndSettle();
    expect(location(), '/register');

    GoRouterNavigator(router).goTo(AppRoute.login);
    await tester.pumpAndSettle();
    expect(location(), '/login');
  });
}

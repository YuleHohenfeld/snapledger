import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/app/app_routes.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/router/app_router.dart';
import 'package:snapledger/core/router/go_router_navigator.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/auth/login/presentation/page/login_page.dart';
import 'package:snapledger/features/auth/splash/presentation/page/splash_page.dart';
import 'package:snapledger/features/expenses/list/presentation/page/expense_list_page.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_session_refresher.dart';
import '../support/fake_user_repository.dart';
import '../support/in_memory_secure_store.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeSessionRefresher refresher;
  late SessionNotifier session;
  late FakeAuthRepository auth;
  late GoRouter router;

  setUp(() {
    refresher = FakeSessionRefresher(() async => const SessionEnded());
    session = SessionNotifier(tokens: TokenStore(InMemorySecureStore()), refresher: refresher);
    auth = FakeAuthRepository();
    router = buildRouter(session, appRoutes);
  });

  tearDown(() {
    router.dispose();
    session.dispose();
  });

  Future<void> pumpRouter(WidgetTester tester) => tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionNotifier>.value(value: session),
        Provider<AuthRepository>.value(value: auth),
        Provider<UserRepository>.value(value: FakeUserRepository()),
        Provider<AppNavigator>.value(value: GoRouterNavigator(router)),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );

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

  testWidgets('a deep link to a tab survives login through from', (tester) async {
    router.go('/expenses');
    await pumpRouter(tester);
    await tester.pumpAndSettle();
    expect(location(), '/login?from=%2Fexpenses');

    await session.signIn(auth.response.tokens);
    await tester.pumpAndSettle();

    expect(location(), '/expenses');
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/app/app_routes.dart';
import 'package:snapledger/core/design/widgets/gradient_button.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/router/app_router.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/categories/_shared/data/repositories/category_repository.dart';
import 'package:snapledger/features/expenses/_shared/data/repositories/expense_repository.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';
import 'package:snapledger/features/summary/_shared/data/repositories/summary_repository.dart';
import 'package:snapledger/features/summary/overview/presentation/widgets/category_breakdown_chart.dart';
import 'package:snapledger/features/summary/overview/presentation/widgets/summary_total_card.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_category_repository.dart';
import '../support/fake_expense_repository.dart';
import '../support/fake_navigator.dart';
import '../support/fake_session_refresher.dart';
import '../support/fake_summary_repository.dart';
import '../support/fake_user_repository.dart';
import '../support/in_memory_secure_store.dart';
import '../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late SessionNotifier session;
  late PendingVerification pending;
  late FakeAuthRepository auth;
  late FakeNavigator navigator;
  late FakeSummaryRepository summaries;
  late GoRouter router;

  setUp(() {
    final refresher = FakeSessionRefresher(() async => const Refreshed('fake-access-1'));
    final tokens = TokenStore(InMemorySecureStore());
    // The sign out only revokes when a refresh token is stored.
    // PT: O logout só revoga quando há um refresh token guardado.
    unawaited(tokens.save(accessToken: 'fake-access-1', refreshToken: 'fake-refresh-1'));
    session = SessionNotifier(tokens: tokens, refresher: refresher);
    pending = PendingVerification(session: session);
    auth = FakeAuthRepository();
    navigator = FakeNavigator();
    summaries = FakeSummaryRepository(
      fallback: fakeSummary(
        expenseCount: 2,
        total: '30.00',
        byCategory: [fakeCategorySummary(total: '30.00', expenseCount: 2, percentage: '100.00')],
      ),
    );
    router = buildRouter(session, pending, appRoutes);
  });

  tearDown(() {
    router.dispose();
    pending.dispose();
    session.dispose();
  });

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    reduceMotion(tester);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionNotifier>.value(value: session),
          Provider<AuthRepository>.value(value: auth),
          ChangeNotifierProvider<PendingVerification>.value(value: pending),
          Provider<UserRepository>.value(value: FakeUserRepository()),
          Provider<CategoryRepository>.value(value: FakeCategoryRepository()),
          Provider<ExpenseRepository>.value(value: FakeExpenseRepository()),
          Provider<SummaryRepository>.value(value: summaries),
          Provider<AppNavigator>.value(value: navigator),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final topTabSummary = find.widgetWithText(TextButton, 'Summary');
  final topTabExpenses = find.widgetWithText(TextButton, 'Expenses');

  group('compact (400 wide)', () {
    testWidgets('shows the bottom bar and no top tabs', (tester) async {
      await pumpShell(tester, const Size(400, 800));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(topTabSummary, findsNothing);
      expect(find.byTooltip(l10n.shellAccountMenuTooltip), findsNothing);
    });

    testWidgets('keeps the add button of the expense list', (tester) async {
      await pumpShell(tester, const Size(400, 800));
      await tester.tap(find.text(l10n.navExpenses));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('medium (700 wide)', () {
    testWidgets('shows a navigation rail with the three destinations', (tester) async {
      await pumpShell(tester, const Size(700, 800));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(topTabSummary, findsNothing);
      expect(find.text(l10n.navProfile), findsOneWidget);
    });

    testWidgets('the rail switches branches and reaches the profile', (tester) async {
      await pumpShell(tester, const Size(700, 800));
      expect(router.routeInformationProvider.value.uri.toString(), '/summary');

      await tester.tap(
        find.descendant(of: find.byType(NavigationRail), matching: find.text('Expenses')),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.toString(), '/expenses');

      await tester.tap(
        find.descendant(of: find.byType(NavigationRail), matching: find.text(l10n.navProfile)),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.toString(), '/profile');
    });
  });

  group('expanded (1280 wide)', () {
    testWidgets('shows the top bar tabs and the account menu, and no bottom bar', (tester) async {
      await pumpShell(tester, const Size(1280, 800));

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(topTabSummary, findsOneWidget);
      expect(topTabExpenses, findsOneWidget);
      expect(find.byTooltip(l10n.shellAccountMenuTooltip), findsOneWidget);
      expect(find.text('SnapLedger'), findsOneWidget);
    });

    testWidgets('marks the current tab as selected for screen readers', (tester) async {
      await pumpShell(tester, const Size(1280, 800));

      expect(
        tester.getSemantics(topTabSummary),
        isSemantics(
          label: 'Summary',
          isSelected: true,
          hasSelectedState: true,
          isButton: true,
          isFocusable: true,
        ),
      );
      expect(
        tester.getSemantics(topTabExpenses),
        isSemantics(label: 'Expenses', isSelected: false, hasSelectedState: true),
      );
    });

    testWidgets('tapping a tab switches the branch', (tester) async {
      await pumpShell(tester, const Size(1280, 800));
      expect(router.routeInformationProvider.value.uri.toString(), '/summary');

      await tester.tap(topTabExpenses);
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.toString(), '/expenses');
    });

    testWidgets('the account menu has Profile, Categories and Sign out', (tester) async {
      await pumpShell(tester, const Size(1280, 800));

      await tester.tap(find.byTooltip(l10n.shellAccountMenuTooltip));
      await tester.pumpAndSettle();

      expect(find.text(l10n.navProfile), findsOneWidget);
      expect(find.text(l10n.profileCategoriesRow), findsOneWidget);
      expect(find.text(l10n.profileLogout), findsOneWidget);
    });

    testWidgets('Categories in the account menu navigates to the categories', (tester) async {
      await pumpShell(tester, const Size(1280, 800));

      await tester.tap(find.byTooltip(l10n.shellAccountMenuTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.profileCategoriesRow));
      await tester.pumpAndSettle();

      expect(navigator.pushed, [AppRoute.categories]);
    });

    testWidgets('Profile in the account menu goes to the profile', (tester) async {
      await pumpShell(tester, const Size(1280, 800));

      await tester.tap(find.byTooltip(l10n.shellAccountMenuTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.navProfile));
      await tester.pumpAndSettle();

      expect(navigator.wentTo, [AppRoute.profile]);
    });

    testWidgets('Sign out revokes the refresh token and ends the session', (tester) async {
      await pumpShell(tester, const Size(1280, 800));
      expect(session.status, SessionStatus.signedIn);

      await tester.tap(find.byTooltip(l10n.shellAccountMenuTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.profileLogout));
      await tester.pumpAndSettle();

      expect(auth.logouts, hasLength(1));
      expect(session.status, SessionStatus.signedOut);
    });

    testWidgets('Sign out is disabled while the sign out runs', (tester) async {
      auth.gate = Completer<void>();
      await pumpShell(tester, const Size(1280, 800));

      await tester.tap(find.byTooltip(l10n.shellAccountMenuTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.profileLogout));
      await tester.pumpAndSettle();
      expect(auth.logouts, hasLength(1));

      await tester.tap(find.byTooltip(l10n.shellAccountMenuTooltip));
      await tester.pumpAndSettle();
      final logoutItem = find.ancestor(
        of: find.text(l10n.profileLogout),
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem && !w.enabled),
      );
      expect(logoutItem, findsOneWidget);

      auth.gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('tapping the current tab returns to its first screen', (tester) async {
      await pumpShell(tester, const Size(1280, 800));
      await tester.tap(topTabExpenses);
      await tester.pumpAndSettle();
      router.go('/expenses/new');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.toString(), '/expenses/new');

      await tester.tap(topTabExpenses);
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.toString(), '/expenses');
    });

    testWidgets('the top bar has no add button', (tester) async {
      await pumpShell(tester, const Size(1280, 800));

      expect(find.byType(GradientButton), findsNothing);
      expect(find.text(l10n.expenseListAdd), findsNothing);
    });

    testWidgets('the expense list has its header button instead of a FAB and title bar', (
      tester,
    ) async {
      await pumpShell(tester, const Size(1280, 800));
      await tester.tap(topTabExpenses);
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text(l10n.expenseListNew), findsOneWidget);
    });

    testWidgets('the summary has the total and the breakdown side by side', (tester) async {
      await pumpShell(tester, const Size(1280, 800));

      final total = tester.getTopLeft(find.byType(SummaryTotalCard));
      final breakdown = tester.getTopLeft(find.byType(CategoryBreakdownChart));
      expect(breakdown.dx, greaterThan(total.dx));
      expect(breakdown.dy, total.dy);
    });
  });

  testWidgets('the summary stacks the total above the breakdown on a compact window', (
    tester,
  ) async {
    await pumpShell(tester, const Size(400, 800));

    final total = tester.getTopLeft(find.byType(SummaryTotalCard));
    final breakdown = tester.getTopLeft(find.byType(CategoryBreakdownChart));
    expect(breakdown.dx, total.dx);
    expect(breakdown.dy, greaterThan(total.dy));
  });
}

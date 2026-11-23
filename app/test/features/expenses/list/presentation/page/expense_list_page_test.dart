import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/l10n/date_format.dart';
import 'package:snapledger/core/l10n/money_format.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/expenses/_shared/data/repositories/expense_repository.dart';
import 'package:snapledger/features/expenses/list/presentation/page/expense_list_page.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../../support/fake_expense_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/fake_user_repository.dart';
import '../../../../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final today = DateTime(2026, 11, 23, 14, 30);

  late FakeExpenseRepository expenses;
  late FakeNavigator navigator;

  String money(String amount) => formatMoney(Decimal.parse(amount), currency: 'BRL', locale: 'en');

  setUp(() {
    expenses = FakeExpenseRepository(
      expenses: [
        fakeExpense(id: 'e1', amount: '10.10', description: 'Lunch', date: DateTime(2026, 11, 23)),
        fakeExpense(id: 'e2', amount: '20.20', description: 'Dinner', date: DateTime(2026, 11, 23)),
        fakeExpense(id: 'e3', amount: '0.30', description: 'Gum', date: DateTime(2026, 11, 22)),
        fakeExpense(id: 'e4', amount: '5.00', description: 'Bus', date: DateTime(2026, 11, 5)),
        fakeExpense(id: 'o1', amount: '99.00', description: 'Old', date: DateTime(2026, 10, 30)),
      ],
    );
    navigator = FakeNavigator();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await pumpApp(
      tester,
      ExpenseListPage(now: () => today),
      providers: [
        Provider<ExpenseRepository>.value(value: expenses),
        Provider<UserRepository>.value(value: FakeUserRepository()),
        Provider<AppNavigator>.value(value: navigator),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the month, its total and the expenses grouped by day', (tester) async {
    await pumpPage(tester);

    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text(l10n.expenseListMonthTotal), findsOneWidget);
    expect(find.text(money('35.60')), findsOneWidget);
    expect(find.text(l10n.expenseListToday), findsOneWidget);
    expect(find.text(l10n.expenseListYesterday), findsOneWidget);
    expect(find.text(formatDayHeader(DateTime(2026, 11, 5), locale: 'en')), findsOneWidget);
    // Day totals: today 10.10 + 20.20, yesterday 0.30, the 5th 5.00.
    // PT: Totais dos dias: hoje 10,10 + 20,20, ontem 0,30, dia 5 5,00.
    expect(find.text(money('30.30')), findsOneWidget);
    expect(find.text(money('0.30')), findsNWidgets(2));
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text(money('10.10')), findsOneWidget);
    expect(find.text('Old'), findsNothing);
  });

  testWidgets('shows the category of each expense, a default translated from its key', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('Groceries'), findsNWidgets(4));
  });

  testWidgets('an empty month shows the empty state and no total', (tester) async {
    expenses.expenses = [];

    await pumpPage(tester);

    expect(find.text(l10n.expenseListEmptyTitle), findsOneWidget);
    expect(find.text(l10n.expenseListEmptyBody), findsOneWidget);
    expect(find.text(l10n.expenseListMonthTotal), findsNothing);
    expect(find.text(l10n.expenseListAdd), findsOneWidget);
  });

  testWidgets('a failed load shows the message and retry loads again', (tester) async {
    expenses.failure = const NetworkFailure();
    await pumpPage(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    expenses.failure = null;
    await tester.tap(find.text(l10n.expenseListRetry));
    await tester.pumpAndSettle();

    expect(find.text('Lunch'), findsOneWidget);
  });

  testWidgets('previous month shows that month; next is off in the current month', (tester) async {
    await pumpPage(tester);
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip(l10n.monthSelectorPrevious));
    await tester.pumpAndSettle();

    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed,
      isNotNull,
    );
  });

  testWidgets('the add button opens the new expense form', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text(l10n.expenseListAdd));

    expect(navigator.pushed, [AppRoute.expenseNew]);
  });

  testWidgets('a wide window has the page header button and no FAB', (tester) async {
    await pumpPage(tester);
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text(l10n.expensesTitle), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, l10n.expenseListNew));

    expect(navigator.pushed, [AppRoute.expenseNew]);
  });

  testWidgets('a compact window has the FAB and no header button', (tester) async {
    await pumpPage(tester);
    tester.view.physicalSize = const Size(400, 900);
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text(l10n.expenseListNew), findsNothing);
  });

  testWidgets('tapping an expense opens its edit form', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Dinner'));

    expect(navigator.pushedExpenseEdits, ['e2']);
  });

  testWidgets('pull to refresh reloads the month', (tester) async {
    await pumpPage(tester);
    final calls = expenses.listCalls;

    await tester.fling(find.text('Lunch'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(expenses.listCalls, calls + 1);
  });

  testWidgets('a saved expense shows up without a manual refresh', (tester) async {
    await pumpPage(tester);
    expect(find.text('Taxi'), findsNothing);

    await expenses.create(fakeRequest(description: 'Taxi', date: DateTime(2026, 11, 23)));
    await tester.pumpAndSettle();

    expect(find.text('Taxi'), findsOneWidget);
  });
}

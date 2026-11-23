import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/l10n/money_format.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/expenses/_shared/data/repositories/expense_repository.dart';
import 'package:snapledger/features/summary/_shared/data/repositories/summary_repository.dart';
import 'package:snapledger/features/summary/overview/presentation/page/summary_page.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../../support/fake_expense_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/fake_summary_repository.dart';
import '../../../../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final today = DateTime(2026, 11, 23, 14, 30);
  const november = Month(2026, 11);

  late FakeSummaryRepository summaries;
  late FakeExpenseRepository expenses;
  late FakeNavigator navigator;

  String money(String amount) => formatMoney(Decimal.parse(amount), currency: 'BRL', locale: 'en');

  void answer({String total = '1000.00', String previous = '800.00'}) {
    summaries.summaries[november] = fakeSummary(
      total: total,
      previousMonthTotal: previous,
      expenseCount: 37,
      byCategory: [
        fakeCategorySummary(),
        fakeCategorySummary(
          id: '0b8a3f52-0000-4000-8000-000000000002',
          name: 'Transport',
          total: '310.00',
          expenseCount: 20,
          percentage: '25.11',
        ),
        fakeCategorySummary(
          id: '0b8a3f52-0000-4000-8000-000000000003',
          name: 'Health',
          total: '4.00',
          expenseCount: 1,
          percentage: '0.40',
        ),
      ],
    );
  }

  setUp(() {
    summaries = FakeSummaryRepository();
    expenses = FakeExpenseRepository();
    navigator = FakeNavigator();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await pumpApp(
      tester,
      SummaryPage(now: () => today),
      providers: [
        Provider<SummaryRepository>.value(value: summaries),
        Provider<ExpenseRepository>.value(value: expenses),
        Provider<AppNavigator>.value(value: navigator),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the month, the total, the count and the comparison', (tester) async {
    answer();
    await pumpPage(tester);

    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text(l10n.summaryTotalLabel), findsOneWidget);
    expect(find.text(money('1000.00')), findsOneWidget);
    expect(find.text(l10n.summaryExpenseCount(37)), findsOneWidget);
    // 1000 against 800: 200.00 more, 25 percent.
    // PT: 1000 contra 800: 200,00 a mais, 25 por cento.
    expect(find.text(l10n.summaryPillUp(l10n.summaryPercent('25.0'))), findsOneWidget);
    expect(find.text(l10n.summaryComparisonUp(money('200.00'))), findsOneWidget);
  });

  testWidgets('a rise smaller than 0.05 percent shows "<0.1%", not "Up 0.0%"', (tester) async {
    answer(total: '1000.00', previous: '999.99');
    await pumpPage(tester);

    expect(find.text(l10n.summaryPillUp(l10n.summaryPercentTiny)), findsOneWidget);
  });

  testWidgets('less than last month says down', (tester) async {
    answer(total: '600.00', previous: '800.00');
    await pumpPage(tester);

    expect(find.text(l10n.summaryPillDown(l10n.summaryPercent('25.0'))), findsOneWidget);
    expect(find.text(l10n.summaryComparisonDown(money('200.00'))), findsOneWidget);
  });

  testWidgets('same as last month says same', (tester) async {
    answer(total: '800.00', previous: '800.00');
    await pumpPage(tester);

    expect(find.text(l10n.summaryPillSame), findsOneWidget);
    expect(find.text(l10n.summaryComparisonSame), findsOneWidget);
  });

  testWidgets('a previous month with no expense shows no percent', (tester) async {
    answer(previous: '0.00');
    await pumpPage(tester);

    expect(find.text(l10n.summaryPillUpNoPercent), findsOneWidget);
    expect(find.textContaining('%'), findsNWidgets(3));
    expect(find.text(l10n.summaryComparisonUp(money('1000.00'))), findsOneWidget);
  });

  testWidgets('draws one ranked bar per category with its API percentage', (tester) async {
    answer();
    await pumpPage(tester);

    expect(find.text(l10n.summaryByCategoryTitle), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text(money('612.30')), findsOneWidget);
    expect(find.text(l10n.summaryCategoryMeta(9, l10n.summaryPercent('49.6'))), findsOneWidget);
    final bars = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .toList();
    expect(bars.map((b) => b.widthFactor), [0.496, 0.2511, 0.02]);
    // Ranked: the first row is above the second.
    // PT: Ranqueado: a primeira linha fica acima da segunda.
    expect(
      tester.getTopLeft(find.text('Groceries')).dy,
      lessThan(tester.getTopLeft(find.text('Transport')).dy),
    );
  });

  testWidgets('each row has one spoken label with name, amount and percent', (tester) async {
    answer();
    final handle = tester.ensureSemantics();
    await pumpPage(tester);

    expect(
      find.bySemanticsLabel(l10n.summaryCategoryRowSemantics('Groceries', money('612.30'), '49.6')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('percent of the total')), findsNWidgets(3));
    // The pieces inside a row are not read again on their own.
    // PT: As peças dentro de uma linha não são lidas de novo sozinhas.
    expect(find.bySemanticsLabel('Groceries'), findsNothing);
    handle.dispose();
  });

  testWidgets('the comparison reads as one sentence', (tester) async {
    answer();
    final handle = tester.ensureSemantics();
    await pumpPage(tester);

    expect(
      find.bySemanticsLabel(
        '${l10n.summaryPillUp(l10n.summaryPercent('25.0'))}. '
        '${l10n.summaryComparisonUp(money('200.00'))}',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('an empty month shows the empty state and Add expense opens the form', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text(l10n.summaryEmptyTitle), findsOneWidget);
    expect(find.text(l10n.summaryTotalLabel), findsNothing);

    await tester.tap(find.text(l10n.summaryEmptyAdd));

    expect(navigator.pushed, [AppRoute.expenseNew]);
  });

  testWidgets('a failed load shows the message and retry loads again', (tester) async {
    answer();
    summaries.failure = const NetworkFailure();
    await pumpPage(tester);
    expect(find.text(l10n.summaryRetry), findsOneWidget);

    summaries.failure = null;
    await tester.tap(find.text(l10n.summaryRetry));
    await tester.pumpAndSettle();

    expect(find.text(money('1000.00')), findsOneWidget);
    expect(find.text(l10n.summaryRetry), findsNothing);
  });

  testWidgets('the month selector goes back, and next is off on the current month', (tester) async {
    answer();
    await pumpPage(tester);
    final next = find.widgetWithIcon(IconButton, Icons.chevron_right);
    expect(tester.widget<IconButton>(next).onPressed, isNull);

    await tester.tap(find.byTooltip(l10n.monthSelectorPrevious));
    await tester.pumpAndSettle();

    expect(find.text('October 2026'), findsOneWidget);
    expect(summaries.fetched, [november, const Month(2026, 10)]);
    expect(tester.widget<IconButton>(next).onPressed, isNotNull);
  });

  testWidgets('pull to refresh reloads the month', (tester) async {
    answer();
    await pumpPage(tester);
    answer(total: '1100.00');

    await tester.fling(find.byType(CustomScrollView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(summaries.calls, 2);
    expect(find.text(money('1100.00')), findsOneWidget);
  });

  testWidgets('a saved expense shows up without a manual refresh', (tester) async {
    await pumpPage(tester);
    expect(find.text(l10n.summaryEmptyTitle), findsOneWidget);
    answer();

    expenses.notifyChanged();
    await tester.pumpAndSettle();

    expect(find.text(money('1000.00')), findsOneWidget);
    expect(find.text(l10n.summaryEmptyTitle), findsNothing);
  });

  testWidgets('a failed refresh keeps the summary and shows the message', (tester) async {
    answer();
    await pumpPage(tester);
    summaries.failure = const NetworkFailure();

    expenses.notifyChanged();
    await tester.pumpAndSettle();

    expect(find.text(money('1000.00')), findsOneWidget);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
  });
}

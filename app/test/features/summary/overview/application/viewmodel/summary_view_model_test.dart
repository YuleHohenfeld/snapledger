import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/summary/overview/application/viewmodel/summary_view_model.dart';

import '../../../../../support/fake_expense_repository.dart';
import '../../../../../support/fake_summary_repository.dart';

void main() {
  final today = DateTime(2026, 11, 23, 14, 30);
  const november = Month(2026, 11);

  late FakeSummaryRepository summaries;
  late FakeExpenseRepository expenses;
  late SummaryViewModel viewModel;

  SummaryLoaded loaded() => viewModel.state as SummaryLoaded;

  void answer({String total = '1234.56', String previous = '980.00', int count = 37}) {
    summaries.summaries[november] = fakeSummary(
      total: total,
      previousMonthTotal: previous,
      expenseCount: count,
      byCategory: [fakeCategorySummary()],
    );
  }

  setUp(() {
    summaries = FakeSummaryRepository();
    expenses = FakeExpenseRepository();
    viewModel = SummaryViewModel(summaries: summaries, expenses: expenses, now: () => today);
  });

  tearDown(() => viewModel.dispose());

  group('load', () {
    test('starts loading the current month, then shows its summary', () async {
      answer();
      expect(viewModel.state, isA<SummaryLoading>());
      expect(viewModel.month, november);

      await viewModel.load();

      expect(loaded().month, november);
      expect(loaded().summary.total, Decimal.parse('1234.56'));
      expect(loaded().isEmpty, isFalse);
      expect(summaries.fetched, [november]);
    });

    test('a month with no expense is empty', () async {
      await viewModel.load();

      expect(loaded().isEmpty, isTrue);
    });

    test('a failure becomes a typed Failed state and load again recovers', () async {
      answer();
      summaries.failure = const NetworkFailure();

      await viewModel.load();
      expect((viewModel.state as SummaryFailed).failure, isA<NetworkFailure>());
      expect(viewModel.state.month, november);

      summaries.failure = null;
      await viewModel.load();
      expect(viewModel.state, isA<SummaryLoaded>());
    });

    test('notifies loading only when there was something else on screen', () async {
      answer();
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      await viewModel.load();
      expect(notifications, 1);

      await viewModel.load();
      expect(notifications, 3);
    });
  });

  group('comparison', () {
    test('up: more than last month, with the exact difference and percent', () async {
      answer(total: '1100.00', previous: '1000.00');

      await viewModel.load();

      expect(loaded().comparison.direction, ComparisonDirection.up);
      expect(loaded().comparison.difference, Decimal.parse('100'));
      expect(loaded().comparison.percent, Decimal.parse('10'));
    });

    test('down: less than last month; difference and percent are positive', () async {
      answer(total: '750.00', previous: '1000.00');

      await viewModel.load();

      expect(loaded().comparison.direction, ComparisonDirection.down);
      expect(loaded().comparison.difference, Decimal.parse('250'));
      expect(loaded().comparison.percent, Decimal.parse('25'));
    });

    test('same: equal totals', () async {
      answer(total: '500.00', previous: '500.00');

      await viewModel.load();

      expect(loaded().comparison.direction, ComparisonDirection.same);
      expect(loaded().comparison.difference, Decimal.zero);
      expect(loaded().comparison.percent, Decimal.zero);
    });

    test('previous month at 0: up with no percent (no division by zero)', () async {
      answer(total: '80.00', previous: '0.00');

      await viewModel.load();

      expect(loaded().comparison.direction, ComparisonDirection.up);
      expect(loaded().comparison.difference, Decimal.parse('80'));
      expect(loaded().comparison.percent, isNull);
    });

    test('a percent that does not end is cut at 4 places, exact in Decimal', () {
      final comparison = MonthComparison.of(Decimal.parse('110.10'), Decimal.parse('100.00'));
      expect(comparison.percent, Decimal.parse('10.1'));

      final repeating = MonthComparison.of(Decimal.parse('1.00'), Decimal.parse('3.00'));
      expect(repeating.percent, Decimal.parse('66.6666'));
    });

    test('money sums like 0.1 + 0.2 stay exact', () {
      final comparison = MonthComparison.of(Decimal.parse('0.30'), Decimal.parse('0.10'));

      expect(comparison.difference, Decimal.parse('0.20'));
      expect(comparison.percent, Decimal.parse('200'));
    });
  });

  group('month navigation', () {
    test('previous loads the month before and shows it in every state', () async {
      await viewModel.load();

      await viewModel.showPreviousMonth();

      expect(viewModel.month, const Month(2026, 10));
      expect(loaded().month, const Month(2026, 10));
      expect(summaries.fetched, [november, const Month(2026, 10)]);
    });

    test('next is off on the current month and does nothing', () async {
      await viewModel.load();
      expect(viewModel.canGoNext, isFalse);

      await viewModel.showNextMonth();

      expect(viewModel.month, november);
      expect(summaries.calls, 1);
    });

    test('going back and forth reaches the current month again', () async {
      await viewModel.load();
      await viewModel.showPreviousMonth();
      expect(viewModel.canGoNext, isTrue);

      await viewModel.showNextMonth();

      expect(viewModel.month, november);
      expect(viewModel.canGoNext, isFalse);
    });

    test('crosses the year boundary', () async {
      viewModel.dispose();
      viewModel = SummaryViewModel(
        summaries: summaries,
        expenses: expenses,
        now: () => DateTime(2026, 1, 5),
      );

      await viewModel.showPreviousMonth();

      expect(viewModel.month, const Month(2025, 12));
    });

    test('a slow answer for an old month does not overwrite the newer one', () async {
      final gate = summaries.gate = Completer<void>();
      summaries.summaries[november] = fakeSummary(total: '1.00', expenseCount: 1);
      final first = viewModel.load();
      summaries.gate = null;

      await viewModel.showPreviousMonth();
      gate.complete();
      await first;

      expect(viewModel.month, const Month(2026, 10));
      expect(loaded().month, const Month(2026, 10));
    });
  });

  group('refresh and reload on changes', () {
    test('a saved expense reloads the summary, which stays on screen meanwhile', () async {
      answer(total: '10.00', previous: '0.00', count: 1);
      await viewModel.load();
      answer(total: '30.00', previous: '0.00', count: 2);
      final gate = summaries.gate = Completer<void>();

      expenses.notifyChanged();
      await pumpEventQueue();
      expect(viewModel.state, isA<SummaryLoaded>());
      expect(loaded().summary.total, Decimal.parse('10.00'));

      gate.complete();
      await pumpEventQueue();

      expect(loaded().summary.total, Decimal.parse('30.00'));
      expect(summaries.calls, 2);
    });

    test('a failed reload keeps the summary and the failure next to it', () async {
      answer();
      await viewModel.load();
      summaries.failure = const NetworkFailure();

      await viewModel.refresh();

      expect(loaded().failure, isA<NetworkFailure>());
      expect(loaded().summary.total, Decimal.parse('1234.56'));

      summaries.failure = null;
      await viewModel.refresh();
      expect(loaded().failure, isNull);
    });

    test('refresh before anything loaded loads (no second concurrent request is kept)', () async {
      answer();

      await viewModel.refresh();

      expect(viewModel.state, isA<SummaryLoaded>());
    });

    test('two quick changes end with the newest answer and one notify per answer kept', () async {
      answer(total: '10.00', previous: '0.00', count: 1);
      await viewModel.load();
      answer(total: '20.00', previous: '0.00', count: 1);

      expenses.notifyChanged();
      answer(total: '30.00', previous: '0.00', count: 1);
      expenses.notifyChanged();
      await pumpEventQueue();

      expect(loaded().summary.total, Decimal.parse('30.00'));
    });
  });

  group('dispose', () {
    test('an answer that arrives after dispose does not notify', () async {
      final gate = summaries.gate = Completer<void>();
      final future = viewModel.load();
      var notified = false;
      viewModel.addListener(() => notified = true);
      viewModel.dispose();

      gate.complete();
      await future;

      expect(notified, isFalse);
    });

    test('stops listening to the repository', () async {
      answer();
      await viewModel.load();
      viewModel.dispose();

      expenses.notifyChanged();
      await pumpEventQueue();

      expect(summaries.calls, 1);
    });

    test('disposing twice is harmless', () {
      viewModel
        ..dispose()
        ..dispose();
    });

    test('load and refresh after dispose do nothing', () async {
      viewModel.dispose();

      await viewModel.load();
      await viewModel.refresh();

      expect(summaries.calls, 0);
    });
  });
}

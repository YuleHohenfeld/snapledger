import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/summary/overview/application/controller/summary_controller.dart';
import 'package:snapledger/features/summary/overview/application/viewmodel/summary_view_model.dart';

import '../../../../../support/fake_expense_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/fake_summary_repository.dart';

void main() {
  late FakeSummaryRepository summaries;
  late FakeExpenseRepository expenses;
  late FakeNavigator navigator;
  late SummaryViewModel viewModel;
  late SummaryController controller;

  setUp(() {
    summaries = FakeSummaryRepository();
    expenses = FakeExpenseRepository();
    navigator = FakeNavigator();
    viewModel = SummaryViewModel(
      summaries: summaries,
      expenses: expenses,
      now: () => DateTime(2026, 11, 23),
    );
    controller = SummaryController(viewModel: viewModel, navigator: navigator);
  });

  tearDown(() => viewModel.dispose());

  test('start loads the current month', () async {
    controller.start();
    await pumpEventQueue();

    expect(viewModel.state, isA<SummaryLoaded>());
    expect(summaries.fetched, [const Month(2026, 11)]);
  });

  test('retry loads again', () async {
    controller.onRetryTapped();
    await pumpEventQueue();

    expect(summaries.calls, 1);
  });

  test('previous and next month taps move the month', () async {
    controller.start();
    await pumpEventQueue();

    controller.onPreviousMonthTapped();
    await pumpEventQueue();
    expect(viewModel.month, const Month(2026, 10));

    controller.onNextMonthTapped();
    await pumpEventQueue();
    expect(viewModel.month, const Month(2026, 11));
  });

  test('next does nothing on the current month', () async {
    controller.start();
    await pumpEventQueue();

    controller.onNextMonthTapped();
    await pumpEventQueue();

    expect(summaries.calls, 1);
  });

  test('refresh reloads and the returned future ends after the answer', () async {
    controller.start();
    await pumpEventQueue();

    await controller.onRefresh();

    expect(summaries.calls, 2);
  });

  test('add expense from the empty state pushes the new expense form', () {
    controller.onAddExpenseTapped();

    expect(navigator.pushed, [AppRoute.expenseNew]);
  });

  test('a save made on the pushed form reloads the summary by itself', () async {
    controller.start();
    await pumpEventQueue();
    controller.onAddExpenseTapped();

    expenses.notifyChanged();
    navigator.completePush();
    await pumpEventQueue();

    expect(summaries.calls, 2);
  });
}

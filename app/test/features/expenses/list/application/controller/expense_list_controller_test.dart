import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/expenses/list/application/controller/expense_list_controller.dart';
import 'package:snapledger/features/expenses/list/application/viewmodel/expense_list_view_model.dart';

import '../../../../../support/fake_expense_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/fake_user_repository.dart';

void main() {
  late FakeExpenseRepository expenses;
  late FakeNavigator navigator;
  late ExpenseListViewModel viewModel;
  late ExpenseListController controller;

  setUp(() {
    expenses = FakeExpenseRepository(expenses: [fakeExpense(id: 'e1', date: DateTime(2026, 11, 20))]);
    navigator = FakeNavigator();
    viewModel = ExpenseListViewModel(
      expenses: expenses,
      users: FakeUserRepository(),
      now: () => DateTime(2026, 11, 23),
    );
    controller = ExpenseListController(viewModel: viewModel, navigator: navigator);
  });

  tearDown(() => viewModel.dispose());

  test('start loads the current month', () async {
    controller.start();
    await pumpEventQueue();

    expect(viewModel.state, isA<ExpenseListLoaded>());
  });

  test('retry loads again', () async {
    controller.onRetryTapped();
    await pumpEventQueue();

    expect(expenses.listCalls, 1);
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

  test('pull to refresh reloads and its future ends with the answer', () async {
    controller.start();
    await pumpEventQueue();
    final calls = expenses.listCalls;

    await controller.onRefresh();

    expect(expenses.listCalls, calls + 1);
  });

  test('the add button pushes the new expense screen', () {
    controller.onAddTapped();

    expect(navigator.pushed, [AppRoute.expenseNew]);
  });

  test('tapping an expense pushes its edit screen by id', () {
    controller.onExpenseTapped(fakeExpense(id: 'e1'));

    expect(navigator.pushedExpenseEdits, ['e1']);
  });
}

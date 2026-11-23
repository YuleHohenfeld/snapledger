import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/expenses/list/application/viewmodel/expense_list_view_model.dart';

import '../../../../../support/fake_expense_repository.dart';
import '../../../../../support/fake_user_repository.dart';

void main() {
  final today = DateTime(2026, 11, 23, 14, 30);

  late FakeExpenseRepository expenses;
  late FakeUserRepository users;
  late ExpenseListViewModel viewModel;

  ExpenseListLoaded loaded() => viewModel.state as ExpenseListLoaded;

  setUp(() {
    expenses = FakeExpenseRepository(
      expenses: [
        fakeExpense(id: 'e1', amount: '10.10', date: DateTime(2026, 11, 23)),
        fakeExpense(id: 'e2', amount: '20.20', date: DateTime(2026, 11, 23)),
        fakeExpense(id: 'e3', amount: '0.30', date: DateTime(2026, 11, 22)),
        fakeExpense(id: 'e4', amount: '5.00', date: DateTime(2026, 11, 5)),
        fakeExpense(id: 'o1', amount: '99.00', date: DateTime(2026, 10, 30)),
      ],
    );
    users = FakeUserRepository();
    viewModel = ExpenseListViewModel(expenses: expenses, users: users, now: () => today);
  });

  tearDown(() => viewModel.dispose());

  group('load', () {
    test('starts loading the current month, then shows the month grouped by day', () async {
      expect(viewModel.state, isA<ExpenseListLoading>());
      expect(viewModel.month, const Month(2026, 11));

      await viewModel.load();

      expect(loaded().month, const Month(2026, 11));
      expect(loaded().currency, 'BRL');
      expect(loaded().days.map((d) => d.date), [
        DateTime(2026, 11, 23),
        DateTime(2026, 11, 22),
        DateTime(2026, 11, 5),
      ]);
      expect(loaded().days.map((d) => d.kind), [
        ExpenseDayKind.today,
        ExpenseDayKind.yesterday,
        ExpenseDayKind.other,
      ]);
      expect(loaded().days.first.expenses.map((e) => e.id), ['e1', 'e2']);
    });

    test('day totals are exact and add up to the month total (0.1 + 0.2 style sums)', () async {
      await viewModel.load();

      expect(loaded().days.map((d) => d.total), [
        Decimal.parse('30.30'),
        Decimal.parse('0.30'),
        Decimal.parse('5.00'),
      ]);
      expect(loaded().monthTotal, Decimal.parse('35.60'));
      expect(
        loaded().days.fold(Decimal.zero, (sum, day) => sum + day.total),
        loaded().monthTotal,
      );
    });

    test('asks the repository for the month once and the user currency once', () async {
      await viewModel.load();

      expect(expenses.listedMonths, [const Month(2026, 11)]);
      expect(users.calls, 1);
    });

    test('an empty month is a loaded state with a zero total', () async {
      expenses.expenses = [];

      await viewModel.load();

      expect(loaded().isEmpty, isTrue);
      expect(loaded().monthTotal, Decimal.zero);
    });

    test('a failure becomes a typed Failed state and load again recovers', () async {
      expenses.failure = const NetworkFailure();
      await viewModel.load();
      expect(viewModel.state, isA<ExpenseListFailed>());
      expect((viewModel.state as ExpenseListFailed).failure, isA<NetworkFailure>());

      expenses.failure = null;
      await viewModel.load();

      expect(viewModel.state, isA<ExpenseListLoaded>());
    });

    test('a failure of the user call also fails the screen', () async {
      users.failure = const NetworkFailure();

      await viewModel.load();

      expect(viewModel.state, isA<ExpenseListFailed>());
    });

    test('the first load does not notify before the data arrives (it is called from initState)', () async {
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      await viewModel.load();

      expect(notifications, 1);
    });
  });

  group('month navigation', () {
    test('next is off in the current month and on in an earlier one', () async {
      await viewModel.load();
      expect(viewModel.canGoNext, isFalse);

      await viewModel.showPreviousMonth();
      expect(viewModel.canGoNext, isTrue);
    });

    test('previous loads the earlier month and shows loading meanwhile', () async {
      await viewModel.load();
      final gate = expenses.gate = Completer<void>();

      final future = viewModel.showPreviousMonth();
      expect(viewModel.state, isA<ExpenseListLoading>());
      expect(viewModel.state.month, const Month(2026, 10));
      gate.complete();
      await future;

      expect(loaded().month, const Month(2026, 10));
      expect(loaded().days.single.expenses.single.id, 'o1');
      expect(users.calls, 1);
    });

    test('next from an earlier month comes back; next beyond the current month does nothing', () async {
      await viewModel.load();
      await viewModel.showPreviousMonth();

      await viewModel.showNextMonth();
      expect(viewModel.month, const Month(2026, 11));
      final calls = expenses.listCalls;
      await viewModel.showNextMonth();

      expect(viewModel.month, const Month(2026, 11));
      expect(expenses.listCalls, calls);
    });

    test('a slow answer for an old month never overwrites the month on screen', () async {
      await viewModel.load();
      final gate = expenses.gate = Completer<void>();
      final slow = viewModel.showPreviousMonth();
      expenses.gate = null;

      await viewModel.showPreviousMonth();
      gate.complete();
      await slow;

      expect(loaded().month, const Month(2026, 9));
    });
  });

  group('refresh and changes', () {
    test('refresh keeps the list on screen and swaps it when the answer arrives', () async {
      await viewModel.load();
      expenses.expenses = [fakeExpense(id: 'n1', amount: '1.00', date: DateTime(2026, 11, 2))];
      final gate = expenses.gate = Completer<void>();

      final future = viewModel.refresh();
      expect(viewModel.state, isA<ExpenseListLoaded>());
      expect(loaded().monthTotal, Decimal.parse('35.60'));
      gate.complete();
      await future;

      expect(loaded().monthTotal, Decimal.parse('1.00'));
    });

    test('a failed refresh keeps the list and the failure next to it', () async {
      await viewModel.load();
      expenses.failure = const NetworkFailure();

      await viewModel.refresh();

      expect(loaded().monthTotal, Decimal.parse('35.60'));
      expect(loaded().failure, isA<NetworkFailure>());
    });

    test('reloads by itself after a successful write (the repository changes)', () async {
      await viewModel.load();
      final before = expenses.listCalls;

      expenses.notifyChanged();
      await pumpEventQueue();

      expect(expenses.listCalls, before + 1);
    });

    test('a write from another screen shows up in the list without a manual refresh', () async {
      await viewModel.load();
      expect(loaded().days.first.expenses, hasLength(2));

      await expenses.create(
        fakeRequest(amount: '3.00', date: DateTime(2026, 11, 23)),
      );
      await pumpEventQueue();

      expect(loaded().days.first.expenses, hasLength(3));
      expect(loaded().monthTotal, Decimal.parse('38.60'));
    });

    test('stops listening once disposed: no notify, no load', () async {
      await viewModel.load();
      final calls = expenses.listCalls;
      viewModel.dispose();

      expenses.notifyChanged();
      await pumpEventQueue();

      expect(expenses.listCalls, calls);
    });

    test('an answer that arrives after dispose does not notify', () async {
      final gate = expenses.gate = Completer<void>();
      final future = viewModel.load();
      var notified = false;
      viewModel.addListener(() => notified = true);
      viewModel.dispose();

      gate.complete();
      await future;

      expect(notified, isFalse);
    });
  });
}

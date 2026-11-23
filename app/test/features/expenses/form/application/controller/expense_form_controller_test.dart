import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/expenses/_shared/validation/expense_validators.dart';
import 'package:snapledger/features/expenses/form/application/controller/expense_form_controller.dart';
import 'package:snapledger/features/expenses/form/application/viewmodel/expense_form_view_model.dart';

import '../../../../../support/fake_category_repository.dart';
import '../../../../../support/fake_expense_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/fake_user_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 11, 23, 14, 30);

  late FakeExpenseRepository expenses;
  late FakeCategoryRepository categories;
  late FakeNavigator navigator;
  late ExpenseFormViewModel viewModel;
  late ExpenseFormController controller;

  Future<void> open({String? id, String locale = 'en'}) async {
    viewModel = ExpenseFormViewModel(
      expenses: expenses,
      categories: categories,
      users: FakeUserRepository(),
      expenseId: id,
    );
    controller = ExpenseFormController(
      viewModel: viewModel,
      navigator: navigator,
      now: () => now,
      locale: locale,
    )..start();
    await pumpEventQueue();
  }

  void fillValid({String amount = '42.90'}) {
    controller.amountField.text = amount;
    controller.descriptionField.text = '  Coffee  ';
    controller.onCategoryPicked(fakeDefaultCategories.first);
  }

  setUp(() {
    expenses = FakeExpenseRepository(
      expenses: [fakeExpense(id: 'e1', amount: '42.90')],
    );
    categories = FakeCategoryRepository();
    navigator = FakeNavigator();
  });

  tearDown(() {
    controller.dispose();
    viewModel.dispose();
  });

  group('opening', () {
    test('a new expense starts on today with no category', () async {
      await open();

      expect(controller.date.value, DateTime(2026, 11, 23));
      expect(controller.category.value, isNull);
      expect(controller.amountField.text, isEmpty);
    });

    test('an existing expense fills the fields from the loaded values', () async {
      await open(id: 'e1');

      expect(controller.amountField.text, '42.90');
      expect(controller.descriptionField.text, 'Weekly groceries');
      expect(controller.date.value, DateTime(2026, 11, 20));
      expect(controller.category.value, fakeDefaultCategories[1]);
    });

    test('the amount is written with the locale separator (pt_BR)', () async {
      await open(id: 'e1', locale: 'pt_BR');

      expect(controller.amountField.text, '42,90');
    });

    test('values typed by the user are not overwritten by a later notification', () async {
      await open(id: 'e1');
      controller.amountField.text = '1.00';

      viewModel.clearFieldError('amount');
      await viewModel.load();

      expect(controller.amountField.text, '1.00');
    });

    test('the day picker starts on the chosen day and stays inside the API range', () async {
      await open();
      expect(controller.pickerStart, DateTime(2026, 11, 23));
      expect(controller.firstDate, DateTime(2000));
      expect(controller.lastDate, DateTime(2026, 11, 24));

      controller.date.value = DateTime(2026, 12, 25);
      expect(controller.pickerStart, DateTime(2026, 11, 24));
      controller.date.value = DateTime(1990);
      expect(controller.pickerStart, DateTime(2000));
    });
  });

  group('preview', () {
    test('shows the typed amount formatted in the user currency, only while it is valid', () async {
      await open();

      controller.amountField.text = '42.9';
      expect(controller.previewText, contains('42.90'));
      expect(controller.previewAmount, Decimal.parse('42.9'));

      controller.amountField.text = '42.999';
      expect(controller.previewText, isNull);
      controller.amountField.text = '0';
      expect(controller.previewText, isNull);
    });
  });

  group('submit', () {
    test('an invalid form calls nothing and marks what is missing', () async {
      await open();

      await controller.onSubmit();

      expect(expenses.created, isEmpty);
      expect(navigator.pops, 0);
      expect(controller.categoryError.value, isTrue);
      expect(controller.dateError.value, isNull);
      expect(controller.amountError(controller.amountField.text), ExpenseAmountError.required);
    });

    test('a missing date is marked', () async {
      await open();
      fillValid();
      controller.date.value = null;

      await controller.onSubmit();

      expect(controller.dateError.value, ExpenseDateError.required);
      expect(expenses.created, isEmpty);
    });

    test(
      'a valid form sends the exact amount, trimmed description, day and category, then pops',
      () async {
        await open();
        fillValid();

        await controller.onSubmit();

        final request = expenses.created.single;
        expect(request.amount, Decimal.parse('42.90'));
        expect(request.description, 'Coffee');
        expect(request.date, DateTime(2026, 11, 23));
        expect(request.categoryId, 'def-food');
        expect(navigator.pops, 1);
      },
    );

    test('pt_BR: 42,90 is read as 42.90', () async {
      await open(locale: 'pt_BR');
      fillValid(amount: '42,90');

      await controller.onSubmit();

      expect(expenses.created.single.amount, Decimal.parse('42.90'));
    });

    test('pt_BR: 42.90 is refused as ambiguous', () async {
      await open(locale: 'pt_BR');
      fillValid(amount: '42.90');

      await controller.onSubmit();

      expect(expenses.created, isEmpty);
    });

    test('editing replaces the existing expense', () async {
      await open(id: 'e1');
      controller.amountField.text = '50';

      await controller.onSubmit();

      expect(expenses.updated.single.$1, 'e1');
      expect(expenses.updated.single.$2.amount, Decimal.parse('50'));
      expect(navigator.pops, 1);
    });

    test('a failed save does not pop and keeps the typed values', () async {
      await open();
      fillValid();
      expenses.writeFailure = const NetworkFailure();

      await controller.onSubmit();

      expect(navigator.pops, 0);
      expect(controller.amountField.text, '42.90');
    });

    test('a double tap saves once', () async {
      await open();
      fillValid();
      final gate = expenses.gate = Completer<void>();

      final first = controller.onSubmit();
      final second = controller.onSubmit();
      gate.complete();
      await Future.wait([first, second]);

      expect(expenses.created, hasLength(1));
      expect(navigator.pops, 1);
    });

    test('does not pop when the screen was disposed while saving', () async {
      await open();
      fillValid();
      final gate = expenses.gate = Completer<void>();

      final submit = controller.onSubmit();
      controller.dispose();
      gate.complete();
      await submit;

      expect(navigator.pops, 0);
    });
  });

  group('server errors', () {
    test('an error on a field is removed when that field is edited, the others stay', () async {
      await open();
      fillValid();
      expenses.writeFailure = const ProblemFailure(
        status: 400,
        type: ProblemType.validationError,
        fieldErrors: ['amount', 'description'],
      );
      await controller.onSubmit();

      controller.onAmountEdited();

      final failure = (viewModel.state as ExpenseFormEditing).failure! as ProblemFailure;
      expect(failure.fieldErrors, ['description']);

      controller.onDescriptionEdited();
      expect((viewModel.state as ExpenseFormEditing).failure, isNull);
    });

    test('picking a date or a category clears their server errors', () async {
      await open();
      fillValid();
      expenses.writeFailure = const ProblemFailure(
        status: 400,
        type: ProblemType.validationError,
        fieldErrors: ['date', 'categoryId'],
      );
      await controller.onSubmit();

      controller.onDatePicked(DateTime(2026, 11, 1, 9));
      expect(((viewModel.state as ExpenseFormEditing).failure! as ProblemFailure).fieldErrors, [
        'categoryId',
      ]);
      controller.onCategoryPicked(fakeDefaultCategories.last);
      expect((viewModel.state as ExpenseFormEditing).failure, isNull);
      expect(controller.date.value, DateTime(2026, 11));
    });

    test('picking clears the device errors too; a cancelled picker changes nothing', () async {
      await open();
      await controller.onSubmit();
      expect(controller.categoryError.value, isTrue);

      controller.onCategoryPicked(fakeDefaultCategories.first);
      expect(controller.categoryError.value, isFalse);

      controller.dateError.value = ExpenseDateError.tooOld;
      controller.onDatePicked(null);
      expect(controller.dateError.value, ExpenseDateError.tooOld);
      controller.onDatePicked(DateTime(2026, 11, 2));
      expect(controller.dateError.value, isNull);
    });
  });

  group('category gone', () {
    test('a save refused for a missing category empties the field and keeps the rest', () async {
      await open(id: 'e1');
      controller.amountField.text = '99.00';
      expenses.writeFailure = const ProblemFailure(status: 404, type: ProblemType.notFound);

      await controller.onSubmit();

      expect((viewModel.state as ExpenseFormEditing).categoryGone, isTrue);
      expect(controller.category.value, isNull);
      expect(controller.amountField.text, '99.00');
      expect(controller.descriptionField.text, 'Weekly groceries');
      expect(navigator.pops, 0);

      controller.onCategoryPicked(fakeDefaultCategories.first);

      expect((viewModel.state as ExpenseFormEditing).categoryGone, isFalse);
      expect(controller.category.value, fakeDefaultCategories.first);
    });
  });

  group('delete', () {
    test('a confirmed delete removes the expense and pops', () async {
      await open(id: 'e1');

      await controller.onDeleteConfirmed();

      expect(expenses.deleted, ['e1']);
      expect(navigator.pops, 1);
    });

    test('a failed delete does not pop', () async {
      await open(id: 'e1');
      expenses.writeFailure = const NetworkFailure();

      await controller.onDeleteConfirmed();

      expect(navigator.pops, 0);
    });
  });

  group('inline category', () {
    test('creates the typed category, chooses it and clears the field', () async {
      await open();
      controller.newCategoryField.text = ' Pets ';

      final created = await controller.onAddCategory();

      expect(created!.name, 'Pets');
      expect(controller.category.value, created);
      expect(controller.newCategoryField.text, isEmpty);
      expect(categories.created, ['Pets']);
    });

    test('an invalid name calls nothing', () async {
      await open();
      controller.newCategoryField.text = '   ';

      expect(await controller.onAddCategory(), isNull);

      expect(categories.created, isEmpty);
      expect(controller.category.value, isNull);
    });

    test('a refused name keeps the text, picks nothing, and its error clears on edit', () async {
      await open();
      controller.newCategoryField.text = 'Food';
      categories.failure = const ProblemFailure(status: 409, type: ProblemType.categoryNameTaken);

      expect(await controller.onAddCategory(), isNull);
      expect((viewModel.state as ExpenseFormEditing).categoryFailure, isNotNull);
      expect(controller.newCategoryField.text, 'Food');
      expect(controller.category.value, isNull);

      controller.onNewCategoryEdited();
      expect((viewModel.state as ExpenseFormEditing).categoryFailure, isNull);
    });
  });

  test('opening the category sheet clears the error of a previous visit', () async {
    await open();
    controller.newCategoryField.text = 'Food';
    categories.failure = const ProblemFailure(status: 409, type: ProblemType.categoryNameTaken);
    await controller.onAddCategory();
    expect((viewModel.state as ExpenseFormEditing).categoryFailure, isNotNull);

    controller.onCategorySheetOpened();

    expect((viewModel.state as ExpenseFormEditing).categoryFailure, isNull);
  });

  group('screen events', () {
    test('back pops and retry loads again', () async {
      await open();
      final calls = categories.listCalls;

      controller.onBackTapped();
      controller.onRetryTapped();
      await pumpEventQueue();

      expect(navigator.pops, 1);
      expect(categories.listCalls, calls + 1);
    });

    test('dispose stops listening: a later load does not touch the released fields', () async {
      await open(id: 'e1');
      controller.dispose();

      await viewModel.load();
    });
  });
}

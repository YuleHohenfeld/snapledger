import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/expenses/form/application/viewmodel/expense_form_view_model.dart';

import '../../../../../support/fake_category_repository.dart';
import '../../../../../support/fake_expense_repository.dart';
import '../../../../../support/fake_user_repository.dart';

void main() {
  late FakeExpenseRepository expenses;
  late FakeCategoryRepository categories;
  late FakeUserRepository users;
  late ExpenseFormViewModel viewModel;

  ExpenseFormEditing editing() => viewModel.state as ExpenseFormEditing;

  ExpenseFormViewModel build({String? id}) => ExpenseFormViewModel(
    expenses: expenses,
    categories: categories,
    users: users,
    expenseId: id,
  );

  ProblemFailure problem(int status, ProblemType type, {List<String> fields = const []}) =>
      ProblemFailure(status: status, type: type, fieldErrors: fields);

  setUp(() {
    expenses = FakeExpenseRepository(expenses: [fakeExpense(id: 'e1')]);
    categories = FakeCategoryRepository(
      categories: [...fakeDefaultCategories, ownCategory('c2', 'travel'), ownCategory('c1', 'Pets')],
    );
    users = FakeUserRepository();
    viewModel = build();
  });

  tearDown(() => viewModel.dispose());

  group('load', () {
    test('create: loading, then editing with the currency and own categories first', () async {
      expect(viewModel.state, isA<ExpenseFormLoading>());

      await viewModel.load();

      expect(editing().currency, 'BRL');
      expect(editing().initial, isNull);
      expect(editing().categories.map((c) => c.id), ['c1', 'c2', 'def-food', 'def-groceries']);
      expect(expenses.fetched, isEmpty);
    });

    test('edit: loads the expense by id, so a deep link works', () async {
      viewModel = build(id: 'e1');

      await viewModel.load();

      expect(expenses.fetched, ['e1']);
      expect(editing().initial, fakeExpense(id: 'e1'));
    });

    test('edit: a missing expense is not-found', () async {
      viewModel = build(id: 'nope');

      await viewModel.load();

      expect(viewModel.state, isA<ExpenseFormNotFound>());
    });

    test('edit: a malformed id (400) is not-found too', () async {
      expenses.failure = problem(400, ProblemType.validationError);
      viewModel = build(id: 'abc');

      await viewModel.load();

      expect(viewModel.state, isA<ExpenseFormNotFound>());
    });

    test('a failure becomes a typed Failed state and load again recovers', () async {
      categories.failure = const NetworkFailure();
      await viewModel.load();
      expect((viewModel.state as ExpenseFormFailed).failure, isA<NetworkFailure>());

      categories.failure = null;
      await viewModel.load();

      expect(viewModel.state, isA<ExpenseFormEditing>());
    });

    test('create mode: a 404 is a failure, not "not found" (there is nothing to find)', () async {
      users.failure = problem(404, ProblemType.notFound);

      await viewModel.load();

      expect(viewModel.state, isA<ExpenseFormFailed>());
    });
  });

  group('save', () {
    setUp(() async => viewModel.load());

    test('create sends the request and ends in Saved', () async {
      final saved = await viewModel.save(fakeRequest());

      expect(saved, isTrue);
      expect(expenses.created, hasLength(1));
      expect(viewModel.state, isA<ExpenseFormSaved>());
    });

    test('edit replaces the expense by id', () async {
      viewModel = build(id: 'e1');
      await viewModel.load();

      final saved = await viewModel.save(fakeRequest(amount: '50.00'));

      expect(saved, isTrue);
      expect(expenses.updated.single.$1, 'e1');
      expect(expenses.updated.single.$2.amount.toStringAsFixed(2), '50.00');
      expect(viewModel.state, isA<ExpenseFormSaved>());
    });

    test('a double submit is one call: the second finds the save running', () async {
      final gate = expenses.gate = Completer<void>();

      final first = viewModel.save(fakeRequest());
      expect(editing().saving, isTrue);
      final second = await viewModel.save(fakeRequest());
      gate.complete();
      final firstResult = await first;

      expect(second, isFalse);
      expect(firstResult, isTrue);
      expect(expenses.created, hasLength(1));
    });

    test('a 400 keeps the form, marks the fields and lets the user try again', () async {
      expenses.writeFailure = problem(400, ProblemType.validationError, fields: ['amount', 'date']);

      final saved = await viewModel.save(fakeRequest());

      expect(saved, isFalse);
      expect(editing().saving, isFalse);
      expect((editing().failure! as ProblemFailure).fieldErrors, ['amount', 'date']);

      expenses.writeFailure = null;
      expect(await viewModel.save(fakeRequest()), isTrue);
    });

    test('a network failure keeps the form with a typed failure', () async {
      expenses.writeFailure = const NetworkFailure();

      await viewModel.save(fakeRequest());

      expect(editing().failure, isA<NetworkFailure>());
      expect(editing().saving, isFalse);
    });

    test('nothing to save before the form is loaded', () async {
      final fresh = build();

      expect(await fresh.save(fakeRequest()), isFalse);
      expect(expenses.created, isEmpty);
      fresh.dispose();
    });
  });

  group('field errors', () {
    setUp(() async {
      await viewModel.load();
      expenses.writeFailure = problem(400, ProblemType.validationError, fields: ['amount', 'date']);
      await viewModel.save(fakeRequest());
    });

    test('editing a field removes only its error', () {
      viewModel.clearFieldError('amount');

      expect((editing().failure! as ProblemFailure).fieldErrors, ['date']);
    });

    test('editing the last failing field removes the failure', () {
      viewModel
        ..clearFieldError('amount')
        ..clearFieldError('date');

      expect(editing().failure, isNull);
    });

    test('editing a field that had no error changes nothing', () {
      final before = editing().failure;

      viewModel.clearFieldError('description');

      expect(editing().failure, same(before));
    });

    test('a form-level failure goes away on any edit', () async {
      expenses.writeFailure = const NetworkFailure();
      await viewModel.save(fakeRequest());
      expect(editing().failure, isA<NetworkFailure>());

      viewModel.clearFieldError('description');

      expect(editing().failure, isNull);
    });
  });

  group('delete', () {
    setUp(() async {
      viewModel = build(id: 'e1');
      await viewModel.load();
    });

    test('deletes by id and ends in Deleted', () async {
      final deleted = await viewModel.delete();

      expect(deleted, isTrue);
      expect(expenses.deleted, ['e1']);
      expect(viewModel.state, isA<ExpenseFormDeleted>());
    });

    test('a failure keeps the form', () async {
      expenses.writeFailure = const NetworkFailure();

      expect(await viewModel.delete(), isFalse);

      expect(editing().failure, isA<NetworkFailure>());
      expect(editing().saving, isFalse);
    });

    test('a 404 (already gone) shows not-found', () async {
      expenses.writeFailure = problem(404, ProblemType.notFound);

      await viewModel.delete();

      expect(viewModel.state, isA<ExpenseFormNotFound>());
    });

    test('a second tap while deleting does nothing', () async {
      final gate = expenses.gate = Completer<void>();

      final first = viewModel.delete();
      expect(await viewModel.delete(), isFalse);
      gate.complete();
      await first;

      expect(expenses.deleted, ['e1']);
    });

    test('there is nothing to delete when creating', () async {
      viewModel = build();
      await viewModel.load();

      expect(await viewModel.delete(), isFalse);
      expect(expenses.deleted, isEmpty);
    });
  });

  group('createCategory', () {
    setUp(() async => viewModel.load());

    test('creates through the category repository, trimmed, and lists it first among own ones', () async {
      final created = await viewModel.createCategory('  Aardvark  ');

      expect(created!.name, 'Aardvark');
      expect(categories.created, ['Aardvark']);
      expect(editing().categories.first.id, created.id);
      expect(editing().categories.map((c) => c.name).take(3), ['Aardvark', 'Pets', 'travel']);
      expect(editing().creatingCategory, isFalse);
    });

    test('a failure is kept apart from the expense failure and clears on edit', () async {
      categories.failure = problem(409, ProblemType.categoryNameTaken);

      final created = await viewModel.createCategory('Pets');

      expect(created, isNull);
      expect(editing().categoryFailure, isA<ProblemFailure>());
      expect(editing().failure, isNull);
      expect(editing().creatingCategory, isFalse);

      viewModel.clearCategoryFailure();
      expect(editing().categoryFailure, isNull);
    });

    test('a second tap while creating does nothing', () async {
      final gate = categories.gate = Completer<void>();

      final first = viewModel.createCategory('Pets 2');
      expect(await viewModel.createCategory('Pets 3'), isNull);
      gate.complete();
      await first;

      expect(categories.created, ['Pets 2']);
    });
  });

  group('dispose', () {
    test('an answer that arrives after dispose does not notify', () async {
      final gate = categories.gate = Completer<void>();
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

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/categories/_shared/data/repositories/category_repository.dart';
import 'package:snapledger/features/expenses/_shared/data/repositories/expense_repository.dart';
import 'package:snapledger/features/expenses/form/presentation/page/expense_form_page.dart';
import 'package:snapledger/features/expenses/form/presentation/widgets/category_picker_sheet.dart';
import 'package:snapledger/features/expenses/form/presentation/widgets/expense_category_field.dart';
import 'package:snapledger/features/expenses/form/presentation/widgets/expense_date_field.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../../support/fake_category_repository.dart';
import '../../../../../support/fake_expense_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/fake_user_repository.dart';
import '../../../../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final today = DateTime(2026, 11, 23, 14, 30);

  late FakeExpenseRepository expenses;
  late FakeCategoryRepository categories;
  late FakeNavigator navigator;

  setUp(() {
    expenses = FakeExpenseRepository(expenses: [fakeExpense(id: 'e1', amount: '42.90')]);
    categories = FakeCategoryRepository(
      categories: [...fakeDefaultCategories, ownCategory('c1', 'Pets')],
    );
    navigator = FakeNavigator();
  });

  Future<void> pumpPage(WidgetTester tester, {String? id}) async {
    await pumpApp(
      tester,
      ExpenseFormPage(expenseId: id, now: () => today),
      providers: [
        Provider<ExpenseRepository>.value(value: expenses),
        Provider<CategoryRepository>.value(value: categories),
        Provider<UserRepository>.value(value: FakeUserRepository()),
        Provider<AppNavigator>.value(value: navigator),
      ],
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> openCategorySheet(WidgetTester tester) async {
    await tester.tap(find.byType(ExpenseCategoryField));
    await tester.pumpAndSettle();
  }

  Future<void> chooseCategory(WidgetTester tester, String name) async {
    await openCategorySheet(tester);
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  // A closing form keeps its busy spinner (the route is popped by the app, not by this fake navigator),
  // so these waits use pump instead of pumpAndSettle.
  // PT: Um formulário fechando mantém o spinner (a rota é fechada pelo app, não por este navigator falso),
  // PT: então estas esperas usam pump em vez de pumpAndSettle.
  Future<void> settleBusy(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text(l10n.expenseFormSave));
    await settleBusy(tester);
  }

  group('creating', () {
    testWidgets('shows the empty form with today as the date', (tester) async {
      await pumpPage(tester);

      expect(find.text(l10n.expenseFormNewTitle), findsOneWidget);
      expect(find.text('Nov 23, 2026'), findsOneWidget);
      expect(find.text(l10n.expenseFormCategoryPlaceholder), findsOneWidget);
      expect(find.byTooltip(l10n.expenseFormDelete), findsNothing);
    });

    testWidgets('saving an empty form shows what is missing and calls nothing', (tester) async {
      await pumpPage(tester);

      await tapSave(tester);

      expect(find.text(l10n.validationRequired), findsNWidgets(2));
      expect(find.text(l10n.expenseFormCategoryRequired), findsOneWidget);
      expect(expenses.created, isEmpty);
      expect(navigator.pops, 0);
    });

    testWidgets('shows the typed amount formatted before saving', (tester) async {
      await pumpPage(tester);

      await tester.enterText(field(l10n.expenseFormAmountLabel), '42.9');
      await tester.pump();

      expect(find.textContaining('42.90'), findsOneWidget);
      expect(find.textContaining('Will be saved as'), findsOneWidget);
    });

    testWidgets('fills the form, picks a category and saves: exact request, then back', (tester) async {
      await pumpPage(tester);

      await tester.enterText(field(l10n.expenseFormAmountLabel), '42.90');
      await tester.enterText(field(l10n.expenseFormDescriptionLabel), 'Coffee');
      await chooseCategory(tester, 'Food');
      await tapSave(tester);

      final request = expenses.created.single;
      expect(request.amount, Decimal.parse('42.90'));
      expect(request.description, 'Coffee');
      expect(request.date, DateTime(2026, 11, 23));
      expect(request.categoryId, 'def-food');
      expect(navigator.pops, 1);
    });

    testWidgets('the date picker changes the day', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byType(ExpenseDateField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Nov 10, 2026'), findsOneWidget);
    });

    testWidgets('a server field error shows under the field and goes away when it is edited', (tester) async {
      await pumpPage(tester);
      await tester.enterText(field(l10n.expenseFormAmountLabel), '42.90');
      await tester.enterText(field(l10n.expenseFormDescriptionLabel), 'Coffee');
      await chooseCategory(tester, 'Food');
      expenses.writeFailure = const ProblemFailure(
        status: 400,
        type: ProblemType.validationError,
        fieldErrors: ['amount'],
      );

      await tapSave(tester);
      expect(find.text(l10n.validationFieldInvalid), findsOneWidget);
      expect(navigator.pops, 0);

      await tester.enterText(field(l10n.expenseFormAmountLabel), '43.90');
      await tester.pump();
      expect(find.text(l10n.validationFieldInvalid), findsNothing);
    });

    testWidgets('a network failure shows a banner and keeps the typed values', (tester) async {
      await pumpPage(tester);
      await tester.enterText(field(l10n.expenseFormAmountLabel), '42.90');
      await tester.enterText(field(l10n.expenseFormDescriptionLabel), 'Coffee');
      await chooseCategory(tester, 'Food');
      expenses.writeFailure = const NetworkFailure();

      await tapSave(tester);

      expect(find.text(l10n.errorNetwork), findsOneWidget);
      expect(find.text('Coffee'), findsOneWidget);
    });
  });

  group('category sheet', () {
    testWidgets('lists the own categories first, then the defaults by their translated name', (tester) async {
      await pumpPage(tester);

      await openCategorySheet(tester);

      expect(find.byType(CategoryPickerSheet), findsOneWidget);
      final tops = ['Pets', 'Food', 'Groceries'].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
      expect(tops, orderedEquals([...tops]..sort()));
    });

    testWidgets('picking a category closes the sheet and shows it in the field', (tester) async {
      await pumpPage(tester);

      await chooseCategory(tester, 'Pets');

      expect(find.byType(CategoryPickerSheet), findsNothing);
      expect(find.text('Pets'), findsOneWidget);
    });

    testWidgets('a new category is created inline, chosen and the sheet closes', (tester) async {
      await pumpPage(tester);
      await openCategorySheet(tester);

      await tester.enterText(field(l10n.categoryPickerNewLabel), 'Travel');
      await tester.tap(find.text(l10n.categoryPickerAdd));
      await tester.pumpAndSettle();

      expect(categories.created, ['Travel']);
      expect(find.byType(CategoryPickerSheet), findsNothing);
      expect(find.text('Travel'), findsOneWidget);
    });

    testWidgets('a refused name shows its error in the sheet and keeps it open', (tester) async {
      await pumpPage(tester);
      await openCategorySheet(tester);
      categories.failure = const ProblemFailure(status: 409, type: ProblemType.categoryNameTaken);

      await tester.enterText(field(l10n.categoryPickerNewLabel), 'Pets');
      await tester.tap(find.text(l10n.categoryPickerAdd));
      await tester.pumpAndSettle();

      expect(find.text(l10n.errorCategoryNameTaken), findsOneWidget);
      expect(find.byType(CategoryPickerSheet), findsOneWidget);
    });
  });

  group('editing', () {
    testWidgets('loads the expense by id and fills the form', (tester) async {
      await pumpPage(tester, id: 'e1');

      expect(find.text(l10n.expenseFormEditTitle), findsOneWidget);
      expect(find.text('42.90'), findsOneWidget);
      expect(find.text('Weekly groceries'), findsOneWidget);
      expect(find.text('Nov 20, 2026'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
    });

    testWidgets('saving replaces the expense', (tester) async {
      await pumpPage(tester, id: 'e1');

      await tester.enterText(field(l10n.expenseFormAmountLabel), '50');
      await tapSave(tester);

      expect(expenses.updated.single.$1, 'e1');
      expect(expenses.updated.single.$2.amount, Decimal.parse('50'));
      expect(navigator.pops, 1);
    });

    testWidgets('delete asks first; cancelling keeps the expense', (tester) async {
      await pumpPage(tester, id: 'e1');

      await tester.tap(find.byTooltip(l10n.expenseFormDelete));
      await tester.pumpAndSettle();
      expect(find.text(l10n.expenseFormDeleteTitle), findsOneWidget);
      await tester.tap(find.text(l10n.expenseFormCancel));
      await tester.pumpAndSettle();

      expect(expenses.deleted, isEmpty);
      expect(navigator.pops, 0);
    });

    testWidgets('delete confirmed removes the expense and goes back', (tester) async {
      await pumpPage(tester, id: 'e1');

      await tester.tap(find.byTooltip(l10n.expenseFormDelete));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.expenseFormDeleteConfirm));
      await settleBusy(tester);

      expect(expenses.deleted, ['e1']);
      expect(navigator.pops, 1);
    });

    testWidgets('an expense that does not exist shows not found and Back leaves', (tester) async {
      await pumpPage(tester, id: 'nope');

      expect(find.text(l10n.expenseFormNotFoundTitle), findsOneWidget);
      expect(find.byTooltip(l10n.expenseFormDelete), findsNothing);
      await tester.tap(find.text(l10n.expenseFormBack));

      expect(navigator.pops, 1);
    });

    testWidgets('a failed load shows the message and retry loads again', (tester) async {
      expenses.failure = const NetworkFailure();
      await pumpPage(tester, id: 'e1');
      expect(find.text(l10n.errorNetwork), findsOneWidget);

      expenses.failure = null;
      await tester.tap(find.text(l10n.expenseListRetry));
      await tester.pumpAndSettle();

      expect(find.text('Weekly groceries'), findsOneWidget);
    });
  });
}

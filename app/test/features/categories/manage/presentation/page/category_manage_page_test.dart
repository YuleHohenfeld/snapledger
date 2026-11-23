import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/_shared/data/repositories/category_repository.dart';
import 'package:snapledger/features/categories/manage/presentation/page/category_manage_page.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../../support/fake_category_repository.dart';
import '../../../../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeCategoryRepository repository;

  setUp(() {
    repository = FakeCategoryRepository(categories: [...fakeDefaultCategories, ownCategory('c1', 'Pets')]);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await pumpApp(
      tester,
      const CategoryManagePage(),
      providers: [Provider<CategoryRepository>.value(value: repository)],
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip(l10n.categoryManageActionsFor(name)));
    await tester.pumpAndSettle();
  }

  testWidgets('shows own categories as written and defaults with a lock', (tester) async {
    await pumpPage(tester);

    expect(find.text('Pets'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
    expect(find.bySemanticsLabel(l10n.categoryManageDefaultLocked('Food')), findsOneWidget);
    // Defaults have no menu: only the own category can be changed.
    // PT: Padrões não têm menu: só a categoria própria pode ser alterada.
    expect(find.byTooltip(l10n.categoryManageActionsFor('Pets')), findsOneWidget);
    expect(find.byTooltip(l10n.categoryManageActionsFor('Food')), findsNothing);
  });

  testWidgets('a default is shown translated from its key, not from the API name', (tester) async {
    repository.categories = const [
      CategoryModel(id: 'def-food', name: 'Comida', isDefault: true, key: 'food'),
    ];

    await pumpPage(tester);

    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Comida'), findsNothing);
  });

  testWidgets('says so when the user has no own category yet', (tester) async {
    repository.categories = [...fakeDefaultCategories];

    await pumpPage(tester);

    expect(find.text(l10n.categoryManageOwnEmpty), findsOneWidget);
  });

  testWidgets('a failed load shows the message and retry loads again', (tester) async {
    repository.failure = const NetworkFailure();
    await pumpPage(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    repository.failure = null;
    await tester.tap(find.text(l10n.categoryManageRetry));
    await tester.pumpAndSettle();

    expect(find.text('Pets'), findsOneWidget);
  });

  testWidgets('adding a category closes the dialog and shows the new row', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text(l10n.categoryManageAdd));
    await tester.pumpAndSettle();
    expect(find.text(l10n.categoryManageCreateTitle), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Gym');
    await tester.tap(find.text(l10n.categoryManageSave));
    await tester.pumpAndSettle();

    expect(repository.created, ['Gym']);
    expect(find.text(l10n.categoryManageCreateTitle), findsNothing);
    expect(find.text('Gym'), findsOneWidget);
  });

  testWidgets('an empty name shows the required error and sends nothing', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text(l10n.categoryManageAdd));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.categoryManageSave));
    await tester.pumpAndSettle();

    expect(find.text(l10n.validationRequired), findsOneWidget);
    expect(repository.created, isEmpty);
    expect(find.text(l10n.categoryManageCreateTitle), findsOneWidget);
  });

  testWidgets('a taken name shows under the field, keeps the dialog, and vanishes on typing', (
    tester,
  ) async {
    await pumpPage(tester);
    repository.failure = const ProblemFailure(status: 409, type: ProblemType.categoryNameTaken);
    await tester.tap(find.text(l10n.categoryManageAdd));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Pets');
    await tester.tap(find.text(l10n.categoryManageSave));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorCategoryNameTaken), findsOneWidget);
    expect(find.text(l10n.categoryManageCreateTitle), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text, 'Pets');

    await tester.enterText(find.byType(TextFormField), 'Pets 2');
    await tester.pump();

    expect(find.text(l10n.errorCategoryNameTaken), findsNothing);
  });

  testWidgets('cancelling the dialog leaves no error behind', (tester) async {
    await pumpPage(tester);
    repository.failure = const ProblemFailure(status: 409, type: ProblemType.categoryNameTaken);
    await tester.tap(find.text(l10n.categoryManageAdd));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Pets');
    await tester.tap(find.text(l10n.categoryManageSave));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.categoryManageCancel));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorCategoryNameTaken), findsNothing);
    expect(find.text(l10n.categoryManageCreateTitle), findsNothing);
  });

  testWidgets('the save button is busy and disabled while the request is in flight', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text(l10n.categoryManageAdd));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Gym');
    repository.gate = Completer<void>();

    await tester.tap(find.text(l10n.categoryManageSave));
    await tester.pump();

    expect(find.bySemanticsLabel(l10n.categoryManageSave), findsOneWidget);
    expect(find.text(l10n.categoryManageSave), findsNothing);

    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(repository.created, ['Gym']);
  });

  testWidgets('renaming starts from the current name', (tester) async {
    await pumpPage(tester);

    await openMenu(tester, 'Pets');
    await tester.tap(find.text(l10n.categoryManageRename));
    await tester.pumpAndSettle();
    expect(find.text(l10n.categoryManageRenameTitle), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text, 'Pets');
    await tester.enterText(find.byType(TextFormField), 'Pet care');
    await tester.tap(find.text(l10n.categoryManageSave));
    await tester.pumpAndSettle();

    expect(repository.renamed, [('c1', 'Pet care')]);
    expect(find.text('Pet care'), findsOneWidget);
    expect(find.text('Pets'), findsNothing);
  });

  testWidgets('deleting asks for confirmation first', (tester) async {
    await pumpPage(tester);

    await openMenu(tester, 'Pets');
    await tester.tap(find.text(l10n.categoryManageDelete));
    await tester.pumpAndSettle();
    expect(find.text(l10n.categoryManageDeleteBody('Pets')), findsOneWidget);

    await tester.tap(find.text(l10n.categoryManageCancel));
    await tester.pumpAndSettle();
    expect(repository.deleted, isEmpty);

    await openMenu(tester, 'Pets');
    await tester.tap(find.text(l10n.categoryManageDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.categoryManageDelete));
    await tester.pumpAndSettle();

    expect(repository.deleted, ['c1']);
    expect(find.text('Pets'), findsNothing);
  });

  testWidgets('deleting a category that still has expenses explains why and keeps it', (tester) async {
    await pumpPage(tester);
    repository.failure = const ProblemFailure(status: 409, type: ProblemType.categoryInUse);

    await openMenu(tester, 'Pets');
    await tester.tap(find.text(l10n.categoryManageDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.categoryManageDelete));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorCategoryInUse), findsOneWidget);
    expect(find.text('Pets'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/categories/_shared/validation/category_validators.dart';
import 'package:snapledger/features/categories/manage/application/controller/category_manage_controller.dart';
import 'package:snapledger/features/categories/manage/application/viewmodel/category_manage_view_model.dart';

import '../../../../../support/fake_category_repository.dart';

void main() {
  // GlobalKey.currentState needs a binding, even with no Form mounted.
  // PT: O GlobalKey.currentState precisa de um binding, mesmo sem Form montado.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCategoryRepository repository;
  late CategoryManageViewModel viewModel;
  late CategoryManageController controller;

  setUp(() async {
    repository = FakeCategoryRepository(categories: [...fakeDefaultCategories, ownCategory('c1', 'Pets')]);
    viewModel = CategoryManageViewModel(categories: repository);
    controller = CategoryManageController(viewModel: viewModel);
    await viewModel.load();
  });

  tearDown(() {
    controller.dispose();
    viewModel.dispose();
  });

  CategoryManageLoaded loaded() => viewModel.state as CategoryManageLoaded;

  test('start loads the categories', () async {
    final fresh = CategoryManageViewModel(categories: repository);
    addTearDown(fresh.dispose);
    final freshController = CategoryManageController(viewModel: fresh);
    addTearDown(freshController.dispose);

    freshController.start();
    await Future<void>.delayed(Duration.zero);

    expect(fresh.state, isA<CategoryManageLoaded>());
  });

  test('saving a new name creates the category', () async {
    controller.beginCreate();
    controller.nameField.text = 'Gym';

    final saved = await controller.onSaveName();

    expect(saved, isTrue);
    expect(controller.isRenaming, isFalse);
    expect(repository.created, ['Gym']);
  });

  test('beginRename fills the field, and saving renames that category', () async {
    controller.beginRename(loaded().own.single);
    expect(controller.nameField.text, 'Pets');
    expect(controller.isRenaming, isTrue);

    controller.nameField.text = 'Pet care';
    final saved = await controller.onSaveName();

    expect(saved, isTrue);
    expect(repository.renamed, [('c1', 'Pet care')]);
  });

  for (final (label, text, error) in [
    ('an empty name', '', CategoryNameError.required),
    ('a name over 40 code points', 'a' * 41, CategoryNameError.tooLong),
    ('a name with a line break', 'a\nb', CategoryNameError.invalidChars),
  ]) {
    test('$label blocks the save without calling the repository', () async {
      controller.beginCreate();
      controller.nameField.text = text;

      final saved = await controller.onSaveName();

      expect(saved, isFalse);
      expect(controller.nameError(text), error);
      expect(repository.created, isEmpty);
    });
  }

  test('a server failure keeps the dialog open (false) and the typed name', () async {
    repository.failure = const ProblemFailure(status: 409, type: ProblemType.categoryNameTaken);
    controller.beginCreate();
    controller.nameField.text = 'Pets';

    final saved = await controller.onSaveName();

    expect(saved, isFalse);
    expect(controller.nameField.text, 'Pets');
    expect(loaded().failure, isNotNull);
  });

  test('editing the name clears the server error', () async {
    repository.failure = const ProblemFailure(status: 409, type: ProblemType.categoryNameTaken);
    controller.beginCreate();
    controller.nameField.text = 'Pets';
    await controller.onSaveName();

    controller.onNameEdited();

    expect(loaded().failure, isNull);
  });

  test('opening the dialog again drops an old failure, and closing it does too', () async {
    repository.failure = const ProblemFailure(status: 409, type: ProblemType.categoryNameTaken);
    controller.beginCreate();
    controller.nameField.text = 'Pets';
    await controller.onSaveName();

    controller.onDialogClosed();
    expect(loaded().failure, isNull);

    repository.failure = const ProblemFailure(status: 404, type: ProblemType.notFound);
    await controller.onDeleteConfirmed(loaded().own.single);
    controller.beginCreate();
    expect(loaded().failure, isNull);
    expect(controller.nameField.text, isEmpty);
  });

  test('delete confirmed deletes the category', () async {
    await controller.onDeleteConfirmed(loaded().own.single);

    expect(repository.deleted, ['c1']);
  });

  test('retry and refresh reload the list', () async {
    final before = repository.listCalls;

    controller.onRetryTapped();
    await Future<void>.delayed(Duration.zero);
    await controller.onRefresh();

    expect(repository.listCalls, before + 2);
  });

  test('dispose releases the text controller and focus node', () {
    final other = CategoryManageController(viewModel: viewModel)..dispose();

    expect(() => other.nameField.addListener(() {}), throwsA(isA<Object>()));
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/categories/manage/application/viewmodel/category_manage_view_model.dart';

import '../../../../../support/fake_category_repository.dart';

void main() {
  late FakeCategoryRepository repository;
  late CategoryManageViewModel viewModel;

  ProblemFailure problem(int status, ProblemType type) => ProblemFailure(status: status, type: type);

  CategoryManageLoaded loaded() => viewModel.state as CategoryManageLoaded;

  setUp(() {
    repository = FakeCategoryRepository(
      categories: [...fakeDefaultCategories, ownCategory('c2', 'travel'), ownCategory('c1', 'Pets')],
    );
    viewModel = CategoryManageViewModel(categories: repository);
  });

  tearDown(() => viewModel.dispose());

  group('load', () {
    test('starts loading, then splits defaults and own (own ordered by name without case)', () async {
      expect(viewModel.state, isA<CategoryManageLoading>());

      await viewModel.load();

      expect(loaded().defaults.map((c) => c.id), ['def-food', 'def-groceries']);
      expect(loaded().own.map((c) => c.name), ['Pets', 'travel']);
      expect(loaded().busy, isFalse);
    });

    test('an empty own list is a valid loaded state', () async {
      repository.categories = [...fakeDefaultCategories];

      await viewModel.load();

      expect(loaded().own, isEmpty);
    });

    test('a failure becomes a typed Failed state, and load again recovers', () async {
      repository.failure = const NetworkFailure();
      await viewModel.load();
      expect(viewModel.state, isA<CategoryManageFailed>());

      repository.failure = null;
      await viewModel.load();

      expect(viewModel.state, isA<CategoryManageLoaded>());
    });

    test('notifies loading again when retrying from a failure', () async {
      repository.failure = const NetworkFailure();
      await viewModel.load();
      repository.failure = null;
      final states = <Type>[];
      viewModel.addListener(() => states.add(viewModel.state.runtimeType));

      await viewModel.load();

      expect(states, [CategoryManageLoading, CategoryManageLoaded]);
    });
  });

  group('refresh', () {
    test('keeps the list on screen and swaps it for the new answer', () async {
      await viewModel.load();
      repository.categories = [...fakeDefaultCategories, ownCategory('c9', 'Gym')];

      await viewModel.refresh();

      expect(loaded().own.map((c) => c.name), ['Gym']);
      expect(loaded().busy, isFalse);
    });

    test('a failed refresh keeps the old list and records the failure', () async {
      await viewModel.load();
      repository.failure = const NetworkFailure();

      await viewModel.refresh();

      expect(loaded().own.map((c) => c.name), ['Pets', 'travel']);
      expect(loaded().failure, isA<NetworkFailure>());
      expect(loaded().busy, isFalse);
    });

    test('before the first load it loads', () async {
      await viewModel.refresh();

      expect(viewModel.state, isA<CategoryManageLoaded>());
    });
  });

  group('create', () {
    setUp(() async => viewModel.load());

    test('adds the category in order, with the name trimmed', () async {
      final ok = await viewModel.create('  Gym ');

      expect(ok, isTrue);
      expect(repository.created, ['Gym']);
      expect(loaded().own.map((c) => c.name), ['Gym', 'Pets', 'travel']);
      expect(loaded().busy, isFalse);
    });

    test('409 category-name-taken keeps the list and the typed failure', () async {
      repository.failure = problem(409, ProblemType.categoryNameTaken);

      final ok = await viewModel.create('Pets');

      expect(ok, isFalse);
      expect(loaded().own, hasLength(2));
      expect(loaded().failure, isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.categoryNameTaken));
      expect(loaded().busy, isFalse);
    });

    test('a second create while the first is in flight is ignored', () async {
      repository.gate = Completer<void>();
      final first = viewModel.create('Gym');
      final second = await viewModel.create('Gym');

      expect(second, isFalse);
      repository.gate!.complete();
      expect(await first, isTrue);
      expect(repository.created, ['Gym']);
    });

    test('a new attempt clears the old failure', () async {
      repository.failure = problem(409, ProblemType.categoryNameTaken);
      await viewModel.create('Pets');
      repository.failure = null;

      await viewModel.create('Other');

      expect(loaded().failure, isNull);
    });
  });

  group('rename', () {
    setUp(() async => viewModel.load());

    test('replaces the name and keeps the order', () async {
      final ok = await viewModel.rename('c1', ' Zoo ');

      expect(ok, isTrue);
      expect(repository.renamed, [('c1', 'Zoo')]);
      expect(loaded().own.map((c) => c.name), ['travel', 'Zoo']);
    });

    test('the same name succeeds without a request', () async {
      final ok = await viewModel.rename('c1', 'Pets');

      expect(ok, isTrue);
      expect(repository.renamed, isEmpty);
    });

    test('only the letter case changing is sent', () async {
      await viewModel.rename('c1', 'pets');

      expect(repository.renamed, [('c1', 'pets')]);
    });

    test('403 on a default keeps the typed failure', () async {
      repository.failure = problem(403, ProblemType.defaultCategoryReadOnly);

      final ok = await viewModel.rename('def-food', 'Meals');

      expect(ok, isFalse);
      expect(
        loaded().failure,
        isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.defaultCategoryReadOnly),
      );
    });

    test('409 name taken and 404 are typed failures', () async {
      repository.failure = problem(409, ProblemType.categoryNameTaken);
      await viewModel.rename('c1', 'Food');
      expect(loaded().failure, isA<ProblemFailure>().having((f) => f.status, 'status', 409));

      repository.failure = problem(404, ProblemType.notFound);
      await viewModel.rename('c1', 'Food');
      expect(loaded().failure, isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.notFound));
    });

    test('404 reloads the stale list and keeps the failure message', () async {
      // Another device deleted c1: the next list no longer has it.
      repository.categories = [...fakeDefaultCategories, ownCategory('c2', 'travel')];
      final before = repository.listCalls;
      repository.failureOnce = problem(404, ProblemType.notFound);

      final ok = await viewModel.rename('c1', 'Food');

      expect(ok, isFalse);
      expect(repository.listCalls, before + 1);
      expect(loaded().own.map((c) => c.id), ['c2']);
      expect(loaded().busy, isFalse);
      expect(loaded().failure, isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.notFound));
    });
  });

  group('delete', () {
    setUp(() async => viewModel.load());

    test('removes the category', () async {
      final ok = await viewModel.delete('c1');

      expect(ok, isTrue);
      expect(repository.deleted, ['c1']);
      expect(loaded().own.map((c) => c.id), ['c2']);
    });

    test('409 category-in-use keeps the category and the typed failure', () async {
      repository.failure = problem(409, ProblemType.categoryInUse);

      final ok = await viewModel.delete('c1');

      expect(ok, isFalse);
      expect(loaded().own, hasLength(2));
      expect(loaded().failure, isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.categoryInUse));
    });

    test('a write before the first load does nothing', () async {
      final fresh = CategoryManageViewModel(categories: repository);
      addTearDown(fresh.dispose);

      expect(await fresh.delete('c1'), isFalse);
      expect(repository.deleted, isEmpty);
    });
  });

  test('clearFailure removes the failure and keeps the list', () async {
    await viewModel.load();
    repository.failure = problem(409, ProblemType.categoryInUse);
    await viewModel.delete('c1');

    viewModel.clearFailure();

    expect(loaded().failure, isNull);
    expect(loaded().own, hasLength(2));
  });

  test('a write blocks a refresh, and a refresh blocks a write', () async {
    await viewModel.load();
    repository.gate = Completer<void>();
    final refresh = viewModel.refresh();

    expect(await viewModel.create('Gym'), isFalse);

    repository.gate!.complete();
    await refresh;
    expect(repository.created, isEmpty);
  });

  test('does not notify after dispose when an answer arrives late', () async {
    final local = CategoryManageViewModel(categories: repository);
    await local.load();
    repository.gate = Completer<void>();
    final pending = local.create('Gym');
    var notified = 0;
    local.addListener(() => notified++);

    local.dispose();
    repository.gate!.complete();
    await pending;

    expect(notified, 0);
  });
}

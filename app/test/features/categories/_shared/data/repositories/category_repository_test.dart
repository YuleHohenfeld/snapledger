import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/api/api_stack.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_request.dart';
import 'package:snapledger/features/categories/_shared/data/repositories/category_repository.dart';

import '../../../../../support/fake_http_adapter.dart';
import '../../../../../support/json_fixtures.dart';

void main() {
  late FakeHttpAdapter adapter;
  late ResponseBody Function() answer;
  late ApiCategoryRepository repository;

  setUp(() {
    answer = () => jsonBody(200, <Object?>[]);
    adapter = FakeHttpAdapter((_) async => answer());
    final config = AppConfig.parse('https://api.test', isRelease: true);
    repository = ApiCategoryRepository(
      ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = adapter),
    );
  });

  test('list GETs /categories and parses defaults and own categories', () async {
    answer = () => jsonBody(200, [
      fakeCategoryJson(id: fakeDefaultCategoryId, name: 'Food', key: 'food'),
      fakeCategoryJson(name: 'Pets'),
    ]);

    final categories = await repository.list();

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.toString(), 'https://api.test/api/v1/categories');
    expect(categories.map((c) => c.id), [fakeDefaultCategoryId, fakeCategoryId]);
    expect(categories.first.key, 'food');
    expect(categories.last.isDefault, isFalse);
  });

  test('list: an element that breaks the contract becomes a ProblemFailure', () async {
    answer = () => jsonBody(200, [
      {'id': 'x'},
    ]);

    await expectLater(repository.list(), throwsA(isA<ProblemFailure>()));
  });

  test('create POSTs {name} and parses the new category', () async {
    answer = () => jsonBody(201, fakeCategoryJson(name: 'Pets'));

    final created = await repository.create(const CategoryRequest(name: 'Pets'));

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/categories');
    expect(request.data, {'name': 'Pets'});
    expect(created.name, 'Pets');
  });

  test('rename PATCHes /categories/{id} with {name}', () async {
    answer = () => jsonBody(200, fakeCategoryJson(name: 'Pet care'));

    final renamed = await repository.rename('c1', const CategoryRequest(name: 'Pet care'));

    final request = adapter.requests.single;
    expect(request.method, 'PATCH');
    expect(request.uri.path, '/api/v1/categories/c1');
    expect(request.data, {'name': 'Pet care'});
    expect(renamed.name, 'Pet care');
  });

  test('delete sends DELETE /categories/{id} and accepts 204', () async {
    answer = () => ResponseBody.fromString('', 204);

    await repository.delete('c1');

    expect(adapter.requests.single.method, 'DELETE');
    expect(adapter.requests.single.uri.path, '/api/v1/categories/c1');
  });

  test('an id is encoded as one path segment', () async {
    answer = () => ResponseBody.fromString('', 204);

    await repository.delete('a/../b');

    expect(adapter.requests.single.uri.path, '/api/v1/categories/a%2F..%2Fb');
  });

  for (final (label, status, slug, type) in [
    ('a taken name', 409, 'category-name-taken', ProblemType.categoryNameTaken),
    ('a category in use', 409, 'category-in-use', ProblemType.categoryInUse),
    ('a default category', 403, 'default-category-read-only', ProblemType.defaultCategoryReadOnly),
    ('a missing category', 404, 'not-found', ProblemType.notFound),
  ]) {
    test('$label becomes a typed ProblemFailure', () async {
      answer = () => problemBody(status, slug);

      await expectLater(
        repository.rename('c1', const CategoryRequest(name: 'x')),
        throwsA(
          isA<ProblemFailure>()
              .having((f) => f.status, 'status', status)
              .having((f) => f.type, 'type', type),
        ),
      );
    });
  }
}

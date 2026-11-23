import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_request.dart';

import '../../../../../support/json_fixtures.dart';

void main() {
  test('parses a default with its key', () {
    final category = CategoryModel.fromJson(
      fakeCategoryJson(id: fakeDefaultCategoryId, name: 'Groceries', key: 'groceries'),
    );

    expect(category.isDefault, isTrue);
    expect(category.key, 'groceries');
    expect(category.name, 'Groceries');
  });

  test('parses an own category with a null key', () {
    final category = CategoryModel.fromJson(fakeCategoryJson());

    expect(category.isDefault, isFalse);
    expect(category.key, isNull);
  });

  test('ignores unknown fields', () {
    expect(CategoryModel.fromJson({...fakeCategoryJson(), 'extra': 1}).id, fakeCategoryId);
  });

  for (final (label, change) in <(String, Map<String, Object?>)>[
    ('a missing id', {'id': null}),
    ('an id that is not a UUID', {'id': 'c1'}),
    ('an empty name', {'name': ''}),
    ('isDefault as text', {'isDefault': 'true'}),
    ('a key that is not text', {'key': 7}),
  ]) {
    test('throws FormatException for $label', () {
      expect(
        () => CategoryModel.fromJson({...fakeCategoryJson(), ...change}),
        throwsFormatException,
      );
    });
  }

  test('throws when the key field is absent (the contract always sends it)', () {
    final json = fakeCategoryJson()..remove('key');

    expect(() => CategoryModel.fromJson(json), throwsFormatException);
  });

  test('toString never shows the name of the category', () {
    final category = CategoryModel.fromJson(fakeCategoryJson(name: 'Secret hobby'));

    expect(category.toString(), isNot(contains('Secret hobby')));
    expect(const CategoryRequest(name: 'Secret hobby').toString(), isNot(contains('Secret hobby')));
  });

  test('the request body is {name}', () {
    expect(const CategoryRequest(name: 'Pets').toJson(), {'name': 'Pets'});
  });
}

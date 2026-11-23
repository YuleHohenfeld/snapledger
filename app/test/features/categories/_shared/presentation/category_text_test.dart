import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/_shared/presentation/category_text.dart';
import 'package:snapledger/features/categories/_shared/validation/category_validators.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('every default key has its own translated name', () {
    const names = {
      'food': 'Food',
      'groceries': 'Groceries',
      'transport': 'Transport',
      'housing': 'Housing',
      'health': 'Health',
      'leisure': 'Leisure',
      'education': 'Education',
      'other': 'Other',
    };
    for (final MapEntry(:key, :value) in names.entries) {
      final category = CategoryModel(id: key, name: 'server-$key', isDefault: true, key: key);
      expect(categoryDisplayName(l10n, category), value, reason: key);
    }
  });

  test('a default with an unknown key falls back to the name the API sent', () {
    const category = CategoryModel(id: 'x', name: 'Pets corner', isDefault: true, key: 'newkey');

    expect(categoryDisplayName(l10n, category), 'Pets corner');
  });

  test('an own category shows its own text as written, even if it looks like a key', () {
    const category = CategoryModel(id: 'x', name: 'food', isDefault: false);

    expect(categoryDisplayName(l10n, category), 'food');
  });

  test('name errors map to localized text', () {
    expect(categoryNameErrorText(l10n, null), isNull);
    expect(categoryNameErrorText(l10n, CategoryNameError.required), l10n.validationRequired);
    expect(
      categoryNameErrorText(l10n, CategoryNameError.tooLong),
      l10n.validationNameTooLong(categoryNameMaxCodePoints),
    );
    expect(
      categoryNameErrorText(l10n, CategoryNameError.invalidChars),
      l10n.validationNameInvalidChars,
    );
  });
}

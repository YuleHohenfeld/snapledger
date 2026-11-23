import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/features/categories/_shared/validation/category_validators.dart';

void main() {
  test('a normal name is valid, with its ends trimmed', () {
    expect(validateCategoryName('Pets'), isNull);
    expect(validateCategoryName('  Pets  '), isNull);
  });

  test('empty or blank is required', () {
    expect(validateCategoryName(null), CategoryNameError.required);
    expect(validateCategoryName(''), CategoryNameError.required);
    expect(validateCategoryName('   '), CategoryNameError.required);
  });

  test('40 code points is the limit, and an emoji counts as one', () {
    expect(validateCategoryName('a' * 40), isNull);
    expect(validateCategoryName('a' * 41), CategoryNameError.tooLong);
    expect(validateCategoryName('😀' * 40), isNull);
    expect(validateCategoryName('😀' * 41), CategoryNameError.tooLong);
  });

  test('control and invisible characters are refused', () {
    expect(validateCategoryName('a\nb'), CategoryNameError.invalidChars);
    expect(validateCategoryName('a\tb'), CategoryNameError.invalidChars);
    expect(validateCategoryName('a​b'), CategoryNameError.invalidChars);
  });
}

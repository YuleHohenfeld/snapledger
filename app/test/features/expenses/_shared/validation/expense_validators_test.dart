import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/features/expenses/_shared/validation/expense_validators.dart';

void main() {
  group('validateExpenseAmount', () {
    ExpenseAmountError? check(String? text, {String locale = 'en', int decimals = 2}) =>
        validateExpenseAmount(text, locale: locale, maxDecimals: decimals);

    test('accepts a normal amount and the largest one', () {
      expect(check('42.90'), isNull);
      expect(check('9999999999.99'), isNull);
      expect(check('0.01'), isNull);
      expect(check('42,90', locale: 'pt_BR'), isNull);
    });

    test('asks for a value when empty or only spaces', () {
      expect(check(null), ExpenseAmountError.required);
      expect(check('  '), ExpenseAmountError.required);
    });

    test('refuses what is not an amount (never guesses)', () {
      expect(check('abc'), ExpenseAmountError.invalid);
      expect(check('1.234'), ExpenseAmountError.invalid);
      expect(check('-5'), ExpenseAmountError.invalid);
      expect(check('42.90', locale: 'pt_BR'), ExpenseAmountError.invalid);
      expect(check('12.5', decimals: 0), ExpenseAmountError.invalid);
    });

    test('refuses zero and anything above the API limit', () {
      expect(check('0'), ExpenseAmountError.notPositive);
      expect(check('0.00'), ExpenseAmountError.notPositive);
      expect(check('10000000000.00'), ExpenseAmountError.tooLarge);
    });
  });

  group('validateExpenseDescription', () {
    test('accepts 1 to 120 code points after trimming', () {
      expect(validateExpenseDescription('Coffee'), isNull);
      expect(validateExpenseDescription('  Coffee  '), isNull);
      expect(validateExpenseDescription('a' * 120), isNull);
    });

    test('an emoji counts as one code point', () {
      expect(validateExpenseDescription('☕' * 120), isNull);
      expect(validateExpenseDescription('😀' * 120), isNull);
      expect(validateExpenseDescription('😀' * 121), ExpenseDescriptionError.tooLong);
    });

    test('refuses empty, too long and invisible characters', () {
      expect(validateExpenseDescription(null), ExpenseDescriptionError.required);
      expect(validateExpenseDescription('   '), ExpenseDescriptionError.required);
      expect(validateExpenseDescription('a' * 121), ExpenseDescriptionError.tooLong);
      expect(validateExpenseDescription('a\nb'), ExpenseDescriptionError.invalidChars);
      expect(validateExpenseDescription('a​b'), ExpenseDescriptionError.invalidChars);
    });
  });

  group('validateExpenseDate', () {
    final now = DateTime(2026, 11, 23, 14, 30);

    test('accepts from 2000-01-01 up to today plus one day', () {
      expect(validateExpenseDate(DateTime(2000), now: now), isNull);
      expect(validateExpenseDate(DateTime(2026, 11, 23), now: now), isNull);
      expect(validateExpenseDate(DateTime(2026, 11, 24, 23, 59), now: now), isNull);
    });

    test('refuses a missing date, one before 2000 and one after tomorrow', () {
      expect(validateExpenseDate(null, now: now), ExpenseDateError.required);
      expect(validateExpenseDate(DateTime(1999, 12, 31), now: now), ExpenseDateError.tooOld);
      expect(validateExpenseDate(DateTime(2026, 11, 25), now: now), ExpenseDateError.tooFarAhead);
    });

    test('the limit crosses a month end', () {
      expect(latestExpenseDate(DateTime(2026, 11, 30, 23)), DateTime(2026, 12));
      expect(latestExpenseDate(DateTime(2026, 12, 31)), DateTime(2027));
    });
  });
}

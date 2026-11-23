import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/l10n/money_input.dart';

void main() {
  Decimal? parse(String text, {String locale = 'en', int maxDecimals = 2}) =>
      parseMoneyInput(text, locale: locale, maxDecimals: maxDecimals);

  test('reads the locale decimal separator', () {
    expect(parse('42,90', locale: 'pt_BR'), Decimal.parse('42.90'));
    expect(parse('42.90'), Decimal.parse('42.90'));
    expect(decimalSeparator('pt_BR'), ',');
    expect(decimalSeparator('en'), '.');
  });

  test('a whole number and one decimal place are valid', () {
    expect(parse('42'), Decimal.parse('42'));
    expect(parse('42.9'), Decimal.parse('42.9'));
    expect(parse(' 7 '), Decimal.parse('7'));
  });

  test('keeps a large value exact', () {
    expect(parse('9999999999.99')!.toStringAsFixed(2), '9999999999.99');
  });

  test('accepts grouping only in groups of three', () {
    expect(parse('1,234.50'), Decimal.parse('1234.50'));
    expect(parse('1.234,50', locale: 'pt_BR'), Decimal.parse('1234.50'));
  });

  test('refuses an ambiguous amount instead of guessing (42.90 in pt_BR is not 4290)', () {
    expect(parse('42.90', locale: 'pt_BR'), isNull);
    expect(parse('1,23.4'), isNull);
  });

  for (final (label, text) in [
    ('three decimals', '1.234'),
    ('empty text', ''),
    ('only spaces', '   '),
    ('a minus sign', '-5'),
    ('a plus sign', '+5'),
    ('an exponent', '1e3'),
    ('a trailing separator', '5.'),
    ('a leading separator', '.5'),
    ('letters', '12a'),
    ('full-width digits', '１２'),
    ('two separators', '1.2.3'),
  ]) {
    test('rejects $label', () => expect(parse(text), isNull));
  }

  test('with no decimals allowed (JPY) a fraction is rejected', () {
    expect(parse('1500', maxDecimals: 0), Decimal.parse('1500'));
    expect(parse('1500.5', maxDecimals: 0), isNull);
  });
}

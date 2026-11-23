import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/l10n/money_format.dart';

void main() {
  String format(String amount, String currency, String locale) =>
      formatMoney(Decimal.parse(amount), currency: currency, locale: locale);

  test('BRL in pt_BR groups with dots and uses a comma', () {
    expect(format('1234.56', 'BRL', 'pt_BR'), 'R\$ 1.234,56');
  });

  test('USD in en groups with commas', () {
    expect(format('1234.5', 'USD', 'en'), '\$1,234.50');
  });

  test('a huge value stays exact (no double in the path)', () {
    expect(format('9999999999.99', 'USD', 'en'), '\$9,999,999,999.99');
  });

  test('JPY shows no decimals for a whole amount', () {
    expect(format('1500', 'JPY', 'en'), '¥1,500');
    expect(format('1500.00', 'JPY', 'en'), '¥1,500');
  });

  test('the largest amount the API accepts formats exactly', () {
    expect(formatMoney(Decimal.parse('9999999999999.99'), currency: 'USD', locale: 'en'), '\$9,999,999,999,999.99');
  });

  test('JPY never hides a cent that exists', () {
    expect(format('12.50', 'JPY', 'en'), '¥12.50');
  });

  test('a negative amount keeps its sign', () {
    expect(format('-5', 'USD', 'en'), '-\$5.00');
  });

  test('currencySymbol gives the short symbol, and the input digits follow the currency', () {
    expect(currencySymbol('BRL', locale: 'pt_BR'), 'R\$');
    expect(currencySymbol('USD', locale: 'en'), '\$');
    expect(moneyInputDigits('BRL', locale: 'pt_BR'), 2);
    expect(moneyInputDigits('JPY', locale: 'en'), 0);
    // BHD has 3 decimals, but the API stores 2: the field never accepts more.
    // PT: BHD tem 3 casas, mas a API guarda 2: o campo nunca aceita mais.
    expect(moneyInputDigits('BHD', locale: 'en'), 2);
  });
}

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/l10n/percent_format.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

void main() {
  test('writes one place by default, with the decimal mark of the locale', () {
    expect(formatPercent(Decimal.parse('49.60'), locale: 'en'), '49.6');
    expect(formatPercent(Decimal.parse('49.60'), locale: 'pt_BR'), '49,6');
  });

  test('pads and rounds half up on Decimal, never through a double', () {
    expect(formatPercent(Decimal.parse('25'), locale: 'en'), '25.0');
    expect(formatPercent(Decimal.parse('0.05'), locale: 'en'), '0.1');
    expect(formatPercent(Decimal.parse('100'), locale: 'en'), '100.0');
  });

  test('can show the two places of the API', () {
    expect(formatPercent(Decimal.parse('49.60'), locale: 'en', fractionDigits: 2), '49.60');
  });

  group('percentText', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    String text(String value) => percentText(l10n, Decimal.parse(value), locale: 'en');

    test('adds the sign from l10n', () {
      expect(text('49.60'), '49.6%');
      expect(text('0'), '0.0%');
    });

    test('shows "<0.1%" only for a value above zero that would round to 0.0', () {
      expect(text('0.01'), '<0.1%');
      expect(text('0.0499'), '<0.1%');
      expect(text('-0.01'), '<0.1%');
      expect(text('0.05'), '0.1%');
    });
  });
}

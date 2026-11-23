import 'package:decimal/decimal.dart';
import 'package:decimal/intl.dart';
import 'package:intl/intl.dart';

/// Formats [amount] for [currency] in [locale] (`R$ 1.234,56`); never hides a cent that exists.
/// PT: Formata [amount] na moeda [currency] e no [locale] (`R$ 1.234,56`); nunca esconde um centavo que existe.
/// Notes: docs/code-notes/app-core.md#money
String formatMoney(Decimal amount, {required String currency, required String locale}) {
  final normal = NumberFormat.simpleCurrency(locale: locale, name: currency);
  final digits = normal.decimalDigits ?? 2;
  // A value that needs more places than the currency usually shows (¥12.50) keeps 2, never rounds.
  // PT: Um valor que precisa de mais casas do que a moeda costuma mostrar (¥12.50) mantém 2, nunca arredonda.
  final fits = (amount * _tenPow(digits)).isInteger;
  final format = fits
      ? normal
      : NumberFormat.simpleCurrency(
          locale: locale,
          name: currency,
          decimalDigits: digits < 2 ? 2 : digits,
        );
  return DecimalFormatter(format).format(amount);
}

/// The symbol of [currency] in [locale] (`R$`, `$`, `¥`), or the code when there is no short symbol.
/// PT: O símbolo de [currency] no [locale] (`R$`, `$`, `¥`), ou o código quando não há símbolo curto.
String currencySymbol(String currency, {required String locale}) =>
    NumberFormat.simpleCurrency(locale: locale, name: currency).currencySymbol;

/// How many decimal places the amount field of [currency] accepts: 0 for JPY, 2 for BRL, at most 2 (the API stores 2).
/// PT: Quantas casas decimais o campo de valor de [currency] aceita: 0 para JPY, 2 para BRL, no máximo 2 (a API guarda 2).
/// Notes: docs/code-notes/app-core.md#money
int moneyInputDigits(String currency, {required String locale}) {
  final digits = NumberFormat.simpleCurrency(locale: locale, name: currency).decimalDigits ?? 2;
  return digits > 2 ? 2 : digits;
}

Decimal _tenPow(int exponent) => Decimal.fromBigInt(BigInt.from(10).pow(exponent));

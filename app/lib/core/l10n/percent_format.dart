import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Writes [value] (`49.60`) with [fractionDigits] places and [locale]'s decimal mark (`49,6`), no `%` sign.
/// Decimal arithmetic only: the text is never a `double`.
/// PT: Escreve [value] (`49.60`) com [fractionDigits] casas e o separador decimal do [locale] (`49,6`), sem o `%`.
/// PT: Só aritmética Decimal: o texto nunca passa por `double`.
/// Notes: docs/code-notes/app-summary.md#percent-text
String formatPercent(Decimal value, {required String locale, int fractionDigits = 1}) {
  final mark = NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;
  return value.toStringAsFixed(fractionDigits).replaceFirst('.', mark);
}

final _half = Decimal.parse('0.05');

/// [value] with its `%` sign from l10n (the language places it); `<0.1%` when it is above zero but would show as `0.0`.
/// PT: [value] com o sinal `%` vindo do l10n (o idioma o posiciona); `<0.1%` quando é maior que zero mas apareceria como `0.0`.
/// Notes: docs/code-notes/app-summary.md#percent-text
String percentText(AppLocalizations l10n, Decimal value, {required String locale}) {
  if (value != Decimal.zero && value.abs() < _half) return l10n.summaryPercentTiny;
  return l10n.summaryPercent(formatPercent(value, locale: locale));
}

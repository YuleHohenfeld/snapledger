import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

/// The decimal separator [locale] writes (`,` in pt_BR, `.` in en); the amount field uses it too.
/// PT: O separador decimal que o [locale] escreve (`,` em pt_BR, `.` em en); o campo de valor o usa também.
String decimalSeparator(String locale) => NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;

/// [amount] as the text of an amount field in [locale] (`42,90` in pt_BR): no grouping, no symbol, and
/// [parseMoneyInput] reads it back to the same value. A value with more places than [maxDecimals] keeps 2.
/// PT: [amount] como o texto de um campo de valor no [locale] (`42,90` em pt_BR): sem agrupamento, sem símbolo, e o
/// PT: [parseMoneyInput] lê de volta o mesmo valor. Um valor com mais casas que [maxDecimals] mantém 2.
/// Notes: docs/code-notes/app-core.md#money
String moneyInputText(Decimal amount, {required String locale, int maxDecimals = 2}) {
  final fits = (amount * Decimal.fromBigInt(BigInt.from(10).pow(maxDecimals))).isInteger;
  final places = fits ? maxDecimals : 2;
  return amount.toStringAsFixed(places).replaceAll('.', decimalSeparator(locale));
}

/// Parses what the user typed into an exact [Decimal], or null when it is not a valid amount.
/// PT: Converte o que o usuário digitou num [Decimal] exato, ou null quando não é um valor válido.
/// Notes: docs/code-notes/app-core.md#money
Decimal? parseMoneyInput(String text, {required String locale, int maxDecimals = 2}) {
  final symbols = NumberFormat.decimalPattern(locale).symbols;
  final decimal = RegExp.escape(symbols.DECIMAL_SEP);
  final group = RegExp.escape(symbols.GROUP_SEP);
  // Digits only (ASCII), grouping only in groups of exactly 3, at most [maxDecimals] places.
  // `42.90` in pt_BR is rejected instead of becoming 4290: an ambiguous amount must never pass.
  // PT: Só dígitos (ASCII), agrupamento só em grupos de exatamente 3, no máximo [maxDecimals] casas.
  // PT: `42.90` em pt_BR é rejeitado em vez de virar 4290: um valor ambíguo nunca pode passar.
  final fraction = maxDecimals > 0 ? '($decimal[0-9]{1,$maxDecimals})?' : '';
  final pattern = RegExp('^([0-9]+|[0-9]{1,3}($group[0-9]{3})+)$fraction\$');
  final trimmed = text.trim();
  if (!pattern.hasMatch(trimmed)) return null;
  // Rebuilt as a plain `1234.50` string for Decimal.parse: no double is ever involved.
  // PT: Remontado como a string simples `1234.50` para o Decimal.parse: nenhum double entra no caminho.
  final normalized = trimmed.replaceAll(symbols.GROUP_SEP, '').replaceAll(symbols.DECIMAL_SEP, '.');
  return Decimal.tryParse(normalized);
}

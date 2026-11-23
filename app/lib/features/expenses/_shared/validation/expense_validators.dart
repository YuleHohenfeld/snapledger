import 'package:decimal/decimal.dart';
import 'package:snapledger/core/l10n/money_input.dart';
import 'package:snapledger/core/time/calendar_date.dart';

/// Why an amount was refused on the device; the View turns it into text.
/// PT: Por que um valor foi recusado no aparelho; a View o transforma em texto.
enum ExpenseAmountError { required, invalid, notPositive, tooLarge }

/// Why a description was refused on the device.
/// PT: Por que uma descrição foi recusada no aparelho.
enum ExpenseDescriptionError { required, tooLong, invalidChars }

/// Why a date was refused on the device.
/// PT: Por que uma data foi recusada no aparelho.
enum ExpenseDateError { required, tooOld, tooFarAhead }

/// Limits copied from docs/api-contract.md (expenses); the API stays the authority.
/// PT: Limites copiados do docs/api-contract.md (gastos); a API continua sendo a autoridade.
const expenseDescriptionMaxCodePoints = 120;

/// The oldest day the API accepts: `2000-01-01`.
/// PT: O dia mais antigo que a API aceita: `2000-01-01`.
final DateTime earliestExpenseDate = DateTime(2000);

final _maxAmount = Decimal.parse('9999999999.99');

// Control (Cc), format (Cf) and lone surrogate (Cs) code points, like the API's NoControlCharacters.
// PT: Code points de controle (Cc), formatação (Cf) e surrogate sozinho (Cs), como o NoControlCharacters da API.
final _invisible = RegExp(r'[\p{Cc}\p{Cf}\p{Cs}]', unicode: true);

/// Amount: typed in [locale], more than zero, at most `9999999999.99`, [maxDecimals] places (never rounded).
/// PT: Valor: digitado no [locale], maior que zero, no máximo `9999999999.99`, [maxDecimals] casas (nunca arredondado).
/// Notes: docs/code-notes/app-expenses.md#validators
ExpenseAmountError? validateExpenseAmount(
  String? value, {
  required String locale,
  required int maxDecimals,
}) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return ExpenseAmountError.required;
  final amount = parseMoneyInput(text, locale: locale, maxDecimals: maxDecimals);
  if (amount == null) return ExpenseAmountError.invalid;
  if (amount <= Decimal.zero) return ExpenseAmountError.notPositive;
  if (amount > _maxAmount) return ExpenseAmountError.tooLarge;
  return null;
}

/// Description: ends trimmed, 1-120 code points (an emoji is one), no invisible characters.
/// PT: Descrição: pontas aparadas, 1-120 code points (um emoji é um), sem caracteres invisíveis.
/// Notes: docs/code-notes/app-expenses.md#validators
ExpenseDescriptionError? validateExpenseDescription(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return ExpenseDescriptionError.required;
  if (_invisible.hasMatch(text)) return ExpenseDescriptionError.invalidChars;
  if (text.runes.length > expenseDescriptionMaxCodePoints) return ExpenseDescriptionError.tooLong;
  return null;
}

/// The latest day the API accepts: today (on the device) plus one day, for devices ahead of UTC.
/// PT: O último dia que a API aceita: hoje (no aparelho) mais um dia, para aparelhos à frente do UTC.
/// Notes: docs/code-notes/app-expenses.md#validators
DateTime latestExpenseDate(DateTime now) => DateTime(now.year, now.month, now.day + 1);

/// Date: from `2000-01-01` up to today plus one day; [now] is injected so tests do not need a clock.
/// PT: Data: de `2000-01-01` até hoje mais um dia; [now] é injetado para os testes não precisarem de relógio.
/// Notes: docs/code-notes/app-expenses.md#validators
ExpenseDateError? validateExpenseDate(DateTime? value, {required DateTime now}) {
  if (value == null) return ExpenseDateError.required;
  final day = calendarDay(value);
  if (day.isBefore(earliestExpenseDate)) return ExpenseDateError.tooOld;
  if (day.isAfter(latestExpenseDate(now))) return ExpenseDateError.tooFarAhead;
  return null;
}

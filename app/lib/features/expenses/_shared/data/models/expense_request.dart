import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:snapledger/core/time/calendar_date.dart';

/// Field names of the contract's `ExpenseRequest`, as the body and `fieldErrors` carry them.
/// PT: Nomes dos campos do `ExpenseRequest` do contrato, como o corpo e o `fieldErrors` os trazem.
/// Notes: docs/code-notes/app-expenses.md#expensemodel
abstract final class ExpenseField {
  static const amount = 'amount';
  static const description = 'description';
  static const date = 'date';
  static const categoryId = 'categoryId';

  /// Every field the form can show an error on.
  /// PT: Todo campo em que o formulário pode mostrar um erro.
  static const all = {amount, description, date, categoryId};
}

/// Body of `POST /expenses` and `PUT /expenses/{id}` (a PUT replaces: every field is sent).
/// PT: Corpo de `POST /expenses` e `PUT /expenses/{id}` (o PUT substitui: todo campo é enviado).
/// Notes: docs/code-notes/app-expenses.md#expensemodel
@immutable
final class ExpenseRequest {
  const ExpenseRequest({
    required this.amount,
    required this.description,
    required this.date,
    required this.categoryId,
  });

  final Decimal amount;
  final String description;

  /// The calendar day; only its year, month and day are sent.
  /// PT: O dia do calendário; só o ano, o mês e o dia são enviados.
  final DateTime date;
  final String categoryId;

  /// The amount goes as a string with exactly 2 places (`"42.90"`), as the contract asks.
  /// PT: O valor vai como string com exatamente 2 casas (`"42.90"`), como o contrato pede.
  Map<String, Object?> toJson() => {
    ExpenseField.amount: amount.toStringAsFixed(2),
    ExpenseField.description: description,
    ExpenseField.date: formatCalendarDate(date),
    ExpenseField.categoryId: categoryId,
  };

  // Amount and description are personal data: `toString` never shows them.
  // PT: Valor e descrição são dados pessoais: o `toString` nunca os mostra.
  @override
  String toString() => 'ExpenseRequest(categoryId: $categoryId)';
}

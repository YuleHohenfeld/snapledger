import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:snapledger/core/time/calendar_date.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

// Same shape as the contract's amount rule: no sign, no exponent, at most 2 places.
// PT: Mesmo formato da regra de valor do contrato: sem sinal, sem expoente, no máximo 2 casas.
final _amountText = RegExp(r'^(0|[1-9][0-9]{0,9})(\.[0-9]{1,2})?$');

/// The contract's `ExpenseResponse`: the amount is an exact [Decimal], the date a calendar day.
/// PT: O `ExpenseResponse` do contrato: o valor é um [Decimal] exato, a data um dia do calendário.
/// Notes: docs/code-notes/app-expenses.md#expensemodel
@immutable
final class ExpenseModel {
  const ExpenseModel({
    required this.id,
    required this.amount,
    required this.description,
    required this.date,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Throws [FormatException] naming the missing or malformed field, never its value.
  /// PT: Lança [FormatException] citando o campo ausente ou malformado, nunca o valor dele.
  factory ExpenseModel.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) throw const FormatException('ExpenseModel.id is missing');
    if (!_uuid.hasMatch(id)) throw const FormatException('ExpenseModel.id is not a UUID');
    final amountText = json['amount'];
    if (amountText is! String || !_amountText.hasMatch(amountText)) {
      throw const FormatException('ExpenseModel.amount is missing or not a decimal string');
    }
    final description = json['description'];
    if (description is! String || description.isEmpty) {
      throw const FormatException('ExpenseModel.description is missing');
    }
    final dateText = json['date'];
    final date = dateText is String ? parseCalendarDate(dateText) : null;
    if (date == null) throw const FormatException('ExpenseModel.date is missing or not yyyy-MM-dd');
    final category = json['category'];
    if (category is! Map<String, Object?>) {
      throw const FormatException('ExpenseModel.category is missing');
    }
    return ExpenseModel(
      id: id,
      amount: Decimal.parse(amountText),
      description: description,
      date: date,
      category: CategoryModel.fromJson(category),
      createdAt: _timestamp(json, 'createdAt'),
      updatedAt: _timestamp(json, 'updatedAt'),
    );
  }

  final String id;

  /// Exact money, read from the contract's string; never a `double`.
  /// PT: Dinheiro exato, lido da string do contrato; nunca um `double`.
  final Decimal amount;
  final String description;

  /// The calendar day, as local midnight (no time zone meaning).
  /// PT: O dia do calendário, como meia-noite local (sem significado de fuso).
  final DateTime date;
  final CategoryModel category;
  final DateTime createdAt;
  final DateTime updatedAt;

  // DateTime.parse would put the raw value in its message, so the error is rebuilt with the name only.
  // PT: O DateTime.parse colocaria o valor bruto na mensagem, então o erro é refeito só com o nome.
  static DateTime _timestamp(Map<String, Object?> json, String field) {
    final value = json[field];
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed != null) return parsed;
    throw FormatException('ExpenseModel.$field is missing or not an ISO-8601 timestamp');
  }

  @override
  bool operator ==(Object other) =>
      other is ExpenseModel &&
      other.id == id &&
      other.amount == amount &&
      other.description == description &&
      other.date == date &&
      other.category == category &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, amount, description, date, category, createdAt, updatedAt);

  // Amount and description are personal data: `toString` never shows them.
  // PT: Valor e descrição são dados pessoais: o `toString` nunca os mostra.
  @override
  String toString() => 'ExpenseModel(id: $id)';
}

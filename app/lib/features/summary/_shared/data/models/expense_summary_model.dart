import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:snapledger/core/time/month.dart';

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

// Money of the summary: no sign, no exponent, 1 or 2 places at most (a month sums many expenses, so no digit limit).
// PT: Dinheiro do resumo: sem sinal, sem expoente, no máximo 2 casas (um mês soma muitos gastos, então sem limite de dígitos).
final _moneyText = RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$');

// A share of the month: 0 to 100 with at most 2 places.
// PT: Uma fatia do mês: de 0 a 100 com no máximo 2 casas.
final _percentText = RegExp(r'^(100(\.0{1,2})?|[1-9]?[0-9](\.[0-9]{1,2})?)$');

final _monthText = RegExp(r'^([0-9]{4})-(0[1-9]|1[0-2])$');

Decimal _money(Map<String, Object?> json, String field, String owner) {
  final value = json[field];
  if (value is! String || !_moneyText.hasMatch(value)) {
    throw FormatException('$owner.$field is missing or not a decimal string');
  }
  return Decimal.parse(value);
}

int _count(Map<String, Object?> json, String field, String owner) {
  final value = json[field];
  if (value is! int || value < 0) {
    throw FormatException('$owner.$field is missing or not a non-negative integer');
  }
  return value;
}

/// One row of the contract's `byCategory`: what a category took from the month.
/// PT: Uma linha do `byCategory` do contrato: o quanto uma categoria levou do mês.
/// Notes: docs/code-notes/app-summary.md#expensesummarymodel
@immutable
final class CategorySummaryModel {
  const CategorySummaryModel({
    required this.categoryId,
    required this.categoryName,
    required this.total,
    required this.expenseCount,
    required this.percentage,
  });

  /// Throws [FormatException] naming the missing or malformed field, never its value.
  /// PT: Lança [FormatException] citando o campo ausente ou malformado, nunca o valor dele.
  factory CategorySummaryModel.fromJson(Map<String, Object?> json) {
    const owner = 'CategorySummaryModel';
    final id = json['categoryId'];
    if (id is! String || id.isEmpty) throw const FormatException('$owner.categoryId is missing');
    if (!_uuid.hasMatch(id)) throw const FormatException('$owner.categoryId is not a UUID');
    final name = json['categoryName'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('$owner.categoryName is missing');
    }
    final percentage = json['percentage'];
    if (percentage is! String || !_percentText.hasMatch(percentage)) {
      throw const FormatException('$owner.percentage is missing or not a percent string');
    }
    return CategorySummaryModel(
      categoryId: id,
      categoryName: name,
      total: _money(json, 'total', owner),
      expenseCount: _count(json, 'expenseCount', owner),
      percentage: Decimal.parse(percentage),
    );
  }

  final String categoryId;

  /// The name as the API sends it: English for a default (the row carries no `key` to translate it).
  /// PT: O nome como a API manda: em inglês numa padrão (a linha não traz `key` para traduzi-lo).
  /// Notes: docs/code-notes/app-summary.md#category-names
  final String categoryName;
  final Decimal total;
  final int expenseCount;

  /// The API's share of the month total (`49.60`), exact; the app never recomputes it.
  /// PT: A fatia do total do mês da API (`49.60`), exata; o app nunca a recalcula.
  final Decimal percentage;

  @override
  bool operator ==(Object other) =>
      other is CategorySummaryModel &&
      other.categoryId == categoryId &&
      other.categoryName == categoryName &&
      other.total == total &&
      other.expenseCount == expenseCount &&
      other.percentage == percentage;

  @override
  int get hashCode => Object.hash(categoryId, categoryName, total, expenseCount, percentage);

  // The name of an own category and the totals are personal data: `toString` never shows them.
  // PT: O nome de uma categoria própria e os totais são dados pessoais: o `toString` nunca os mostra.
  @override
  String toString() => 'CategorySummaryModel(categoryId: $categoryId)';
}

/// The contract's summary of one month: totals, the previous month's total and the ranking per category.
/// PT: O resumo de um mês do contrato: totais, o total do mês anterior e o ranking por categoria.
/// Notes: docs/code-notes/app-summary.md#expensesummarymodel
@immutable
final class ExpenseSummaryModel {
  const ExpenseSummaryModel({
    required this.month,
    required this.currency,
    required this.total,
    required this.expenseCount,
    required this.previousMonthTotal,
    required this.byCategory,
  });

  /// Throws [FormatException] naming the missing or malformed field, never its value.
  /// PT: Lança [FormatException] citando o campo ausente ou malformado, nunca o valor dele.
  factory ExpenseSummaryModel.fromJson(Map<String, Object?> json) {
    const owner = 'ExpenseSummaryModel';
    final monthText = json['month'];
    final match = monthText is String ? _monthText.firstMatch(monthText) : null;
    if (match == null) throw const FormatException('$owner.month is missing or not YYYY-MM');
    final currency = json['currency'];
    if (currency is! String || currency.isEmpty) {
      throw const FormatException('$owner.currency is missing');
    }
    final rows = json['byCategory'];
    if (rows is! List<Object?>) throw const FormatException('$owner.byCategory is not a list');
    return ExpenseSummaryModel(
      month: Month(int.parse(match.group(1)!), int.parse(match.group(2)!)),
      currency: currency,
      total: _money(json, 'total', owner),
      expenseCount: _count(json, 'expenseCount', owner),
      previousMonthTotal: _money(json, 'previousMonthTotal', owner),
      byCategory: List.unmodifiable([
        for (final row in rows)
          if (row is Map<String, Object?>)
            CategorySummaryModel.fromJson(row)
          else
            throw const FormatException('$owner.byCategory has an item that is not an object'),
      ]),
    );
  }

  final Month month;

  /// ISO 4217 code of the user's currency, for `formatMoney`.
  /// PT: Código ISO 4217 da moeda do usuário, para o `formatMoney`.
  final String currency;
  final Decimal total;
  final int expenseCount;

  /// `0.00` when the previous month has no expense.
  /// PT: `0.00` quando o mês anterior não tem gasto.
  final Decimal previousMonthTotal;

  /// Only categories with expenses, biggest total first (the server's order).
  /// PT: Só categorias com gastos, maior total primeiro (a ordem do servidor).
  final List<CategorySummaryModel> byCategory;

  @override
  bool operator ==(Object other) =>
      other is ExpenseSummaryModel &&
      other.month == month &&
      other.currency == currency &&
      other.total == total &&
      other.expenseCount == expenseCount &&
      other.previousMonthTotal == previousMonthTotal &&
      listEquals(other.byCategory, byCategory);

  @override
  int get hashCode => Object.hash(
    month,
    currency,
    total,
    expenseCount,
    previousMonthTotal,
    Object.hashAll(byCategory),
  );

  // The totals are personal data: `toString` never shows them.
  // PT: Os totais são dados pessoais: o `toString` nunca os mostra.
  @override
  String toString() => 'ExpenseSummaryModel(month: ${month.toQuery()})';
}

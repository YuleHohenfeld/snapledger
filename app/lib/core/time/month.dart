import 'package:flutter/foundation.dart';

/// A calendar month with no time zone: the unit of the expense list and the summary (`YYYY-MM`).
/// PT: Um mês do calendário sem fuso: a unidade da lista de gastos e do resumo (`YYYY-MM`).
/// Notes: docs/code-notes/app-core.md#month
@immutable
final class Month implements Comparable<Month> {
  /// [month] is 1 to 12; anything else is a programming error.
  /// PT: [month] vai de 1 a 12; qualquer outro valor é erro de programação.
  const Month(this.year, this.month) : assert(month >= 1 && month <= 12, 'month must be 1..12');

  /// The month that holds [date]; only its year and month are read (the device's local calendar day).
  /// PT: O mês que contém [date]; só o ano e o mês são lidos (o dia local do calendário do aparelho).
  factory Month.of(DateTime date) => Month(date.year, date.month);

  final int year;
  final int month;

  Month get previous => month == 1 ? Month(year - 1, 12) : Month(year, month - 1);

  Month get next => month == 12 ? Month(year + 1, 1) : Month(year, month + 1);

  /// The `month` query value of the contract: `2026-03`.
  /// PT: O valor do parâmetro `month` do contrato: `2026-03`.
  String toQuery() => '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  /// Whether [date] falls in this month; compares the date's own year and month, with no conversion.
  /// PT: Se [date] cai neste mês; compara o ano e o mês da própria data, sem conversão.
  bool contains(DateTime date) => date.year == year && date.month == month;

  /// The first day of the month, at local midnight.
  /// PT: O primeiro dia do mês, à meia-noite local.
  DateTime get firstDay => DateTime(year, month);

  @override
  int compareTo(Month other) => year != other.year ? year - other.year : month - other.month;

  bool operator <(Month other) => compareTo(other) < 0;

  bool operator >(Month other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is Month && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => 'Month(${toQuery()})';
}

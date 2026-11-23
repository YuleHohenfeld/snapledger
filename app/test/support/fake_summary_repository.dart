import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/summary/_shared/data/models/expense_summary_model.dart';
import 'package:snapledger/features/summary/_shared/data/repositories/summary_repository.dart';

/// A [SummaryRepository] answering from [summaries] by month (or [fallback]), recording calls, or throwing [failure].
/// PT: Um [SummaryRepository] que responde de [summaries] por mês (ou [fallback]), registrando chamadas, ou lançando [failure].
class FakeSummaryRepository implements SummaryRepository {
  FakeSummaryRepository({this.fallback, Map<Month, ExpenseSummaryModel>? summaries})
    : summaries = summaries ?? {};

  /// Answers for months not in [summaries]; when null such a month gets an empty summary.
  /// PT: Responde meses que não estão em [summaries]; quando nulo esse mês recebe um resumo vazio.
  ExpenseSummaryModel? fallback;
  final Map<Month, ExpenseSummaryModel> summaries;

  /// Thrown instead of answering when set.
  /// PT: Lançada em vez da resposta quando definida.
  Exception? failure;

  /// When set, every call waits for it, so a test can act while the request is in flight.
  /// PT: Quando definido, toda chamada espera por ele, para o teste agir com a requisição em andamento.
  Completer<void>? gate;

  int calls = 0;
  final List<Month> fetched = [];

  @override
  Future<ExpenseSummaryModel> fetch(Month month) async {
    calls++;
    fetched.add(month);
    await gate?.future;
    if (failure case final failure?) throw failure;
    return summaries[month] ?? fallback ?? fakeSummary(month: month);
  }
}

/// A summary with sensible defaults; money and percentages are read exactly from strings.
/// PT: Um resumo com padrões razoáveis; dinheiro e porcentagens são lidos exatamente de strings.
ExpenseSummaryModel fakeSummary({
  Month month = const Month(2026, 11),
  String currency = 'BRL',
  String total = '0.00',
  int expenseCount = 0,
  String previousMonthTotal = '0.00',
  List<CategorySummaryModel> byCategory = const [],
}) => ExpenseSummaryModel(
  month: month,
  currency: currency,
  total: Decimal.parse(total),
  expenseCount: expenseCount,
  previousMonthTotal: Decimal.parse(previousMonthTotal),
  byCategory: byCategory,
);

CategorySummaryModel fakeCategorySummary({
  String id = '0b8a3f52-0000-4000-8000-000000000001',
  String name = 'Groceries',
  String total = '612.30',
  int expenseCount = 9,
  String percentage = '49.60',
}) => CategorySummaryModel(
  categoryId: id,
  categoryName: name,
  total: Decimal.parse(total),
  expenseCount: expenseCount,
  percentage: Decimal.parse(percentage),
);

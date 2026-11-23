import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/summary/_shared/data/models/expense_summary_model.dart';

/// The summary call of the contract; it throws [ApiFailure].
/// PT: A chamada de resumo do contrato; ela lança [ApiFailure].
/// Notes: docs/code-notes/app-summary.md#summaryrepository
abstract interface class SummaryRepository {
  /// `GET /expenses/summary?month=`: totals, previous month and the ranking per category.
  /// PT: `GET /expenses/summary?month=`: totais, mês anterior e o ranking por categoria.
  Future<ExpenseSummaryModel> fetch(Month month);
}

/// [SummaryRepository] over the [ApiClient], with the contract's path.
/// PT: [SummaryRepository] sobre o [ApiClient], com o caminho do contrato.
/// Notes: docs/code-notes/app-summary.md#summaryrepository
final class ApiSummaryRepository implements SummaryRepository {
  const ApiSummaryRepository(this._api);

  final ApiClient _api;

  @override
  Future<ExpenseSummaryModel> fetch(Month month) async {
    final json = await _api.getJson('/expenses/summary', query: {'month': month.toQuery()});
    // A 2xx body that breaks the contract becomes a ProblemFailure, so callers handle one failure type.
    // PT: Um corpo 2xx que quebra o contrato vira ProblemFailure, então quem chama trata um só tipo de falha.
    try {
      return ExpenseSummaryModel.fromJson(json);
    } on FormatException {
      throw const ProblemFailure(status: 200, type: ProblemType.unknown);
    }
  }
}

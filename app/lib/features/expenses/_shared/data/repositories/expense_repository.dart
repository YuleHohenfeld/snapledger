import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_model.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_request.dart';

/// The expense calls of the contract; every method throws [ApiFailure].
/// PT: As chamadas de gasto do contrato; todo método lança [ApiFailure].
/// Notes: docs/code-notes/app-expenses.md#expenserepository
abstract interface class ExpenseRepository {
  /// Fires after every write the server accepted, so open lists reload without a manual refresh.
  /// PT: Dispara depois de toda escrita que o servidor aceitou, para as listas abertas recarregarem sem atualizar à mão.
  Listenable get changes;

  /// `GET /expenses?month=&categoryId=`: newest day first, as the server ordered them.
  /// PT: `GET /expenses?month=&categoryId=`: dia mais novo primeiro, na ordem do servidor.
  Future<List<ExpenseModel>> listMonth(Month month, {String? categoryId});

  /// `GET /expenses/{id}`.
  Future<ExpenseModel> get(String id);

  /// `POST /expenses`.
  Future<ExpenseModel> create(ExpenseRequest request);

  /// `PUT /expenses/{id}`: replaces the whole expense.
  Future<ExpenseModel> update(String id, ExpenseRequest request);

  /// `DELETE /expenses/{id}`.
  Future<void> delete(String id);

  /// Releases [changes].
  void dispose();
}

/// [ExpenseRepository] over the [ApiClient], with the contract's paths.
/// PT: [ExpenseRepository] sobre o [ApiClient], com os caminhos do contrato.
/// Notes: docs/code-notes/app-expenses.md#expenserepository
final class ApiExpenseRepository implements ExpenseRepository {
  ApiExpenseRepository(this._api);

  final ApiClient _api;
  final _changes = _ChangeSignal();

  @override
  Listenable get changes => _changes;

  @override
  Future<List<ExpenseModel>> listMonth(Month month, {String? categoryId}) async {
    final items = await _api.getJsonList(
      '/expenses',
      query: {'month': month.toQuery(), 'categoryId': ?categoryId},
    );
    return _parse(() => [for (final item in items) ExpenseModel.fromJson(item)]);
  }

  @override
  Future<ExpenseModel> get(String id) async {
    final json = await _api.getJson(_path(id));
    return _parse(() => ExpenseModel.fromJson(json));
  }

  @override
  Future<ExpenseModel> create(ExpenseRequest request) async {
    final json = await _api.postJson('/expenses', request.toJson());
    // The server already stored it: lists reload even if the answer body is unreadable.
    // PT: O servidor já guardou: as listas recarregam mesmo que o corpo da resposta seja ilegível.
    _changes.fire();
    return _parse(() => ExpenseModel.fromJson(json));
  }

  @override
  Future<ExpenseModel> update(String id, ExpenseRequest request) async {
    final json = await _api.putJson(_path(id), request.toJson());
    _changes.fire();
    return _parse(() => ExpenseModel.fromJson(json));
  }

  @override
  Future<void> delete(String id) async {
    await _api.deleteNoContent(_path(id));
    _changes.fire();
  }

  @override
  void dispose() => _changes.dispose();

  String _path(String id) => '/expenses/${Uri.encodeComponent(id)}';

  // A 2xx body that breaks the contract becomes a ProblemFailure, so callers handle one failure type.
  // PT: Um corpo 2xx que quebra o contrato vira ProblemFailure, então quem chama trata um só tipo de falha.
  T _parse<T>(T Function() build) {
    try {
      return build();
    } on FormatException {
      throw const ProblemFailure(status: 200, type: ProblemType.unknown);
    }
  }
}

// A ChangeNotifier whose notify is public to this file only.
// PT: Um ChangeNotifier cujo notify é público só neste arquivo.
class _ChangeSignal extends ChangeNotifier {
  void fire() => notifyListeners();
}

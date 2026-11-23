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

  /// Fires [changes] without a write of ours: a caller that learned the expense is gone (a `GET` 404)
  /// makes the open lists drop it.
  /// PT: Dispara [changes] sem uma escrita nossa: quem descobriu que o gasto sumiu (um `GET` 404) faz as listas abertas o largarem.
  void notifyChanged();

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
  bool _disposed = false;

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
    _notifyChanged();
    return _parse(() => ExpenseModel.fromJson(json));
  }

  @override
  Future<ExpenseModel> update(String id, ExpenseRequest request) async {
    // A PUT 404 is ambiguous (expense gone, or category gone): it does not fire; the ViewModel finds out.
    // PT: Um PUT 404 é ambíguo (gasto sumiu, ou categoria sumiu): não dispara; o ViewModel descobre qual.
    // Notes: docs/code-notes/app-expenses.md#expenserepository
    final json = await _api.putJson(_path(id), request.toJson());
    _notifyChanged();
    return _parse(() => ExpenseModel.fromJson(json));
  }

  @override
  Future<void> delete(String id) async {
    // A DELETE 404 only means the expense is gone: lists reload so they stop showing it.
    // PT: Um DELETE 404 só significa que o gasto sumiu: as listas recarregam para parar de mostrá-lo.
    // Notes: docs/code-notes/app-expenses.md#expenserepository
    try {
      await _api.deleteNoContent(_path(id));
    } on ProblemFailure catch (failure) {
      if (failure.type == ProblemType.notFound) _notifyChanged();
      rethrow;
    }
    _notifyChanged();
  }

  @override
  void notifyChanged() => _notifyChanged();

  @override
  void dispose() {
    _disposed = true;
    _changes.dispose();
  }

  // An answer that arrives after dispose must not notify a released notifier.
  // PT: Uma resposta que chega após o dispose não deve notificar um notifier liberado.
  void _notifyChanged() {
    if (!_disposed) _changes.fire();
  }

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

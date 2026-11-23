import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_model.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_request.dart';
import 'package:snapledger/features/expenses/_shared/data/repositories/expense_repository.dart';

import 'fake_category_repository.dart';

/// An [ExpenseRepository] over an in-memory list, recording calls and firing [changes] after a write
/// that worked, like the real one; or throwing [failure].
/// PT: Um [ExpenseRepository] sobre uma lista em memória, registrando chamadas e disparando [changes] após uma
/// PT: escrita que deu certo, como o real; ou lançando [failure].
class FakeExpenseRepository implements ExpenseRepository {
  FakeExpenseRepository({List<ExpenseModel>? expenses}) : expenses = expenses ?? [];

  /// What the calls answer from, in the order given (the API's order is newest first).
  /// PT: De onde as chamadas respondem, na ordem dada (a ordem da API é a mais nova primeiro).
  List<ExpenseModel> expenses;

  /// Thrown by every call instead of answering when set.
  /// PT: Lançada por toda chamada em vez de responder quando definida.
  Exception? failure;

  /// Thrown by writes only (create, update, delete), when set.
  /// PT: Lançada só por escritas (criar, atualizar, apagar), quando definida.
  Exception? writeFailure;

  /// Thrown by [get] only, when set (a write that failed and then the check of the expense failed too).
  /// PT: Lançada só pelo [get], quando definida (uma escrita que falhou e depois a checagem do gasto também falhou).
  Exception? getFailure;

  /// When set, every call waits for it, so a test can act while the request is in flight.
  /// PT: Quando definido, toda chamada espera por ele, para o teste agir com a requisição em andamento.
  Completer<void>? gate;

  int listCalls = 0;
  final List<Month> listedMonths = [];
  final List<String?> listedCategoryIds = [];
  final List<String> fetched = [];
  final List<ExpenseRequest> created = [];
  final List<(String, ExpenseRequest)> updated = [];
  final List<String> deleted = [];
  int _nextId = 1;

  final _changes = _Signal();
  bool disposed = false;

  @override
  Listenable get changes => _changes;

  @override
  Future<List<ExpenseModel>> listMonth(Month month, {String? categoryId}) async {
    listCalls++;
    listedMonths.add(month);
    listedCategoryIds.add(categoryId);
    await _enter();
    return [
      for (final expense in expenses)
        if (month.contains(expense.date) &&
            (categoryId == null || expense.category.id == categoryId))
          expense,
    ];
  }

  @override
  Future<ExpenseModel> get(String id) async {
    fetched.add(id);
    await _enter();
    if (getFailure case final failure?) throw failure;
    return expenses.firstWhere(
      (e) => e.id == id,
      orElse: () => throw const ProblemFailure(status: 404, type: ProblemType.notFound),
    );
  }

  @override
  Future<ExpenseModel> create(ExpenseRequest request) async {
    await _enterWrite();
    created.add(request);
    final expense = _from('new-${_nextId++}', request);
    expenses = [expense, ...expenses];
    _changes.fire();
    return expense;
  }

  @override
  Future<ExpenseModel> update(String id, ExpenseRequest request) async {
    await _enterWrite();
    updated.add((id, request));
    final expense = _from(id, request);
    expenses = [for (final e in expenses) e.id == id ? expense : e];
    _changes.fire();
    return expense;
  }

  @override
  Future<void> delete(String id) async {
    await _enterWrite();
    deleted.add(id);
    expenses = [
      for (final e in expenses)
        if (e.id != id) e,
    ];
    _changes.fire();
  }

  /// Fires [changes] as if another screen had written.
  /// PT: Dispara [changes] como se outra tela tivesse escrito.
  @override
  void notifyChanged() => _changes.fire();

  @override
  void dispose() {
    disposed = true;
    _changes.dispose();
  }

  ExpenseModel _from(String id, ExpenseRequest request) => ExpenseModel(
    id: id,
    amount: request.amount,
    description: request.description,
    date: request.date,
    category: fakeDefaultCategories.firstWhere(
      (c) => c.id == request.categoryId,
      orElse: () => ownCategory(request.categoryId, 'Own'),
    ),
    createdAt: DateTime.utc(2026, 11, 20),
    updatedAt: DateTime.utc(2026, 11, 20),
  );

  Future<void> _enter() async {
    await gate?.future;
    if (failure case final failure?) throw failure;
  }

  Future<void> _enterWrite() async {
    await _enter();
    if (writeFailure case final failure?) throw failure;
  }
}

class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// A request body with sensible defaults, for writes through the fake.
/// PT: Um corpo de requisição com padrões razoáveis, para escritas pelo fake.
ExpenseRequest fakeRequest({
  String amount = '42.90',
  String description = 'Weekly groceries',
  DateTime? date,
  String? categoryId,
}) => ExpenseRequest(
  amount: Decimal.parse(amount),
  description: description,
  date: date ?? DateTime(2026, 11, 20),
  categoryId: categoryId ?? fakeDefaultCategories[1].id,
);

/// An expense with sensible defaults; [amount] is read exactly (`'42.90'`), [date] is a calendar day.
/// PT: Um gasto com padrões razoáveis; [amount] é lido exatamente (`'42.90'`), [date] é um dia do calendário.
ExpenseModel fakeExpense({
  String id = 'e1',
  String amount = '42.90',
  String description = 'Weekly groceries',
  DateTime? date,
  CategoryModel? category,
}) => ExpenseModel(
  id: id,
  amount: Decimal.parse(amount),
  description: description,
  date: date ?? DateTime(2026, 11, 20),
  category: category ?? fakeDefaultCategories[1],
  createdAt: DateTime.utc(2026, 11, 20, 12),
  updatedAt: DateTime.utc(2026, 11, 20, 12),
);

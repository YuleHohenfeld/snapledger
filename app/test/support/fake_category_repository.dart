import 'dart:async';

import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_request.dart';
import 'package:snapledger/features/categories/_shared/data/repositories/category_repository.dart';

/// A [CategoryRepository] over an in-memory list, recording calls, or throwing [failure].
/// PT: Um [CategoryRepository] sobre uma lista em memória, registrando chamadas, ou lançando [failure].
class FakeCategoryRepository implements CategoryRepository {
  FakeCategoryRepository({List<CategoryModel>? categories})
    : categories = categories ?? [...fakeDefaultCategories];

  /// What [list] answers (defaults first, as the API does).
  /// PT: O que [list] responde (padrões primeiro, como a API faz).
  List<CategoryModel> categories;

  /// Thrown instead of answering when set.
  /// PT: Lançada em vez da resposta quando definida.
  Exception? failure;

  /// Thrown by the next write only (not by [list]), then cleared.
  /// PT: Lançada só pela próxima escrita (não por [list]), depois limpa.
  Exception? failureOnce;

  /// When set, every call waits for it, so a test can act while the request is in flight.
  /// PT: Quando definido, toda chamada espera por ele, para o teste agir com a requisição em andamento.
  Completer<void>? gate;

  int listCalls = 0;
  final List<String> created = [];
  final List<(String, String)> renamed = [];
  final List<String> deleted = [];
  int _nextId = 1;

  @override
  Future<List<CategoryModel>> list() async {
    listCalls++;
    await _enter();
    return List.of(categories);
  }

  @override
  Future<CategoryModel> create(CategoryRequest request) async {
    await _enter();
    created.add(request.name);
    return CategoryModel(
      id: 'own-${_nextId++}',
      name: request.name,
      isDefault: false,
    );
  }

  @override
  Future<CategoryModel> rename(String id, CategoryRequest request) async {
    await _enter();
    if (failureOnce case final once?) {
      failureOnce = null;
      throw once;
    }
    renamed.add((id, request.name));
    return CategoryModel(id: id, name: request.name, isDefault: false);
  }

  @override
  Future<void> delete(String id) async {
    await _enter();
    deleted.add(id);
  }

  Future<void> _enter() async {
    await gate?.future;
    if (failure case final failure?) throw failure;
  }
}

/// Two of the eight defaults, enough for tests (the English name is the API's fallback).
/// PT: Duas das oito padrões, suficiente para os testes (o nome em inglês é o fallback da API).
const fakeDefaultCategories = [
  CategoryModel(id: 'def-food', name: 'Food', isDefault: true, key: 'food'),
  CategoryModel(id: 'def-groceries', name: 'Groceries', isDefault: true, key: 'groceries'),
];

/// An own category (no key).
/// PT: Uma categoria própria (sem key).
CategoryModel ownCategory(String id, String name) =>
    CategoryModel(id: id, name: name, isDefault: false);

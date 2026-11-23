import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_request.dart';

/// The category calls of the contract; every method throws [ApiFailure].
/// PT: As chamadas de categoria do contrato; todo método lança [ApiFailure].
/// Notes: docs/code-notes/app-categories.md#categoryrepository
abstract interface class CategoryRepository {
  /// `GET /categories`: defaults first, then the user's own, as the server ordered them.
  /// PT: `GET /categories`: padrões primeiro, depois as do usuário, na ordem do servidor.
  Future<List<CategoryModel>> list();

  /// `POST /categories`.
  Future<CategoryModel> create(CategoryRequest request);

  /// `PATCH /categories/{id}`.
  Future<CategoryModel> rename(String id, CategoryRequest request);

  /// `DELETE /categories/{id}`.
  Future<void> delete(String id);
}

/// [CategoryRepository] over the [ApiClient], with the contract's paths.
/// PT: [CategoryRepository] sobre o [ApiClient], com os caminhos do contrato.
/// Notes: docs/code-notes/app-categories.md#categoryrepository
final class ApiCategoryRepository implements CategoryRepository {
  const ApiCategoryRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<CategoryModel>> list() async {
    final items = await _api.getJsonList('/categories');
    return _parse(() => [for (final item in items) CategoryModel.fromJson(item)]);
  }

  @override
  Future<CategoryModel> create(CategoryRequest request) async {
    final json = await _api.postJson('/categories', request.toJson());
    return _parse(() => CategoryModel.fromJson(json));
  }

  @override
  Future<CategoryModel> rename(String id, CategoryRequest request) async {
    final json = await _api.patchJson('/categories/${Uri.encodeComponent(id)}', request.toJson());
    return _parse(() => CategoryModel.fromJson(json));
  }

  @override
  Future<void> delete(String id) => _api.deleteNoContent('/categories/${Uri.encodeComponent(id)}');

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

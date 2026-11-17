import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/profile/_shared/data/models/user_model.dart';

/// The signed-in user's profile calls; changing name or currency waits for `PATCH /users/me`.
/// PT: As chamadas do perfil do usuário logado; trocar nome ou moeda espera o `PATCH /users/me`.
/// Notes: docs/code-notes/app-profile.md#userrepository
abstract interface class UserRepository {
  /// `GET /users/me`; throws [ApiFailure].
  /// PT: `GET /users/me`; lança [ApiFailure].
  Future<UserModel> fetchCurrent();
}

/// [UserRepository] over the [ApiClient], with the contract's path.
/// PT: [UserRepository] sobre o [ApiClient], com o caminho do contrato.
/// Notes: docs/code-notes/app-profile.md#userrepository
final class ApiUserRepository implements UserRepository {
  const ApiUserRepository(this._api);

  final ApiClient _api;

  @override
  Future<UserModel> fetchCurrent() async {
    final json = await _api.getJson('/users/me');
    try {
      return UserModel.fromJson(json);
    } on FormatException {
      // A 2xx body that breaks the contract becomes a ProblemFailure, so callers handle one failure type.
      // PT: Um corpo 2xx que quebra o contrato vira ProblemFailure, então quem chama trata um só tipo de falha.
      throw const ProblemFailure(status: 200, type: ProblemType.unknown);
    }
  }
}

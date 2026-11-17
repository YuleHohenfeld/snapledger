import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/profile/_shared/data/models/user_model.dart';

/// The signed-in user's email verification calls (codes live 15 minutes and work once).
/// PT: As chamadas de verificação de email do usuário logado (códigos duram 15 minutos e valem uma vez).
/// Notes: docs/code-notes/app-auth.md#verifyemailviewmodel
abstract interface class EmailVerificationRepository {
  /// `POST /users/me/email-verification` (`202`); throws [ApiFailure] (`429 too-many-requests`).
  /// PT: `POST /users/me/email-verification` (`202`); lança [ApiFailure] (`429 too-many-requests`).
  Future<void> sendCode();

  /// `POST /users/me/email-verification/confirm` (`200`); throws [ApiFailure] (`400 invalid-code`).
  /// PT: `POST /users/me/email-verification/confirm` (`200`); lança [ApiFailure] (`400 invalid-code`).
  Future<UserModel> confirm(String code);
}

/// [EmailVerificationRepository] over the [ApiClient], with the contract's paths and bodies.
/// PT: [EmailVerificationRepository] sobre o [ApiClient], com os caminhos e corpos do contrato.
/// Notes: docs/code-notes/app-auth.md#verifyemailviewmodel
final class ApiEmailVerificationRepository implements EmailVerificationRepository {
  const ApiEmailVerificationRepository(this._api);

  final ApiClient _api;

  @override
  Future<void> sendCode() => _api.postNoContent('/users/me/email-verification');

  @override
  Future<UserModel> confirm(String code) async {
    final json = await _api.postJson('/users/me/email-verification/confirm', {'code': code});
    try {
      return UserModel.fromJson(json);
    } on FormatException {
      // A 2xx body that breaks the contract becomes a ProblemFailure, so callers handle one failure type.
      // PT: Um corpo 2xx que quebra o contrato vira ProblemFailure, então quem chama trata um só tipo de falha.
      throw const ProblemFailure(status: 200, type: ProblemType.unknown);
    }
  }
}

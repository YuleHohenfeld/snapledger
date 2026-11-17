import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/auth/_shared/data/models/auth_response.dart';
import 'package:snapledger/features/auth/_shared/data/models/login_request.dart';
import 'package:snapledger/features/auth/_shared/data/models/password_reset_requests.dart';
import 'package:snapledger/features/auth/_shared/data/models/register_request.dart';
import 'package:snapledger/features/auth/_shared/data/models/reset_grant.dart';

/// The public `/auth/*` calls a screen needs; refresh is not here (core/api owns it).
/// PT: As chamadas públicas de `/auth/*` que uma tela precisa; o refresh não está aqui (é do core/api).
/// Notes: docs/code-notes/app-auth.md#authrepository
abstract interface class AuthRepository {
  /// Creates the account and its first session; throws [ApiFailure].
  /// PT: Cria a conta e a primeira sessão dela; lança [ApiFailure].
  Future<AuthResponse> register(RegisterRequest request);

  /// Starts a session; throws [ApiFailure] (`invalid-credentials` on a wrong email or password).
  /// PT: Inicia uma sessão; lança [ApiFailure] (`invalid-credentials` com email ou senha errados).
  Future<AuthResponse> login(LoginRequest request);

  /// Revokes the session of [refreshToken] on the server; throws [ApiFailure].
  /// PT: Revoga no servidor a sessão de [refreshToken]; lança [ApiFailure].
  Future<void> logout(String refreshToken);

  /// `POST /auth/password-reset` (`202`, always for a well-formed request); throws [ApiFailure].
  /// PT: `POST /auth/password-reset` (`202`, sempre para um pedido bem formado); lança [ApiFailure].
  Future<void> requestPasswordReset(PasswordResetRequest request);

  /// `POST /auth/password-reset/verify` (`200`); throws [ApiFailure] (`400 invalid-code`, `429`).
  /// PT: `POST /auth/password-reset/verify` (`200`); lança [ApiFailure] (`400 invalid-code`, `429`).
  Future<ResetGrant> verifyPasswordResetCode(PasswordResetVerifyRequest request);

  /// `POST /auth/password-reset/confirm` (`204`); throws [ApiFailure] (`400 invalid-reset-token`, `429`).
  /// PT: `POST /auth/password-reset/confirm` (`204`); lança [ApiFailure] (`400 invalid-reset-token`, `429`).
  Future<void> confirmPasswordReset(PasswordResetConfirmRequest request);
}

/// [AuthRepository] over the [ApiClient], with the contract's paths and bodies.
/// PT: [AuthRepository] sobre o [ApiClient], com os caminhos e corpos do contrato.
/// Notes: docs/code-notes/app-auth.md#authrepository
final class ApiAuthRepository implements AuthRepository {
  const ApiAuthRepository(this._api);

  final ApiClient _api;

  @override
  Future<AuthResponse> register(RegisterRequest request) async =>
      _parse(201, await _api.postJson('/auth/register', request.toJson()));

  @override
  Future<AuthResponse> login(LoginRequest request) async =>
      _parse(200, await _api.postJson('/auth/login', request.toJson()));

  @override
  Future<void> logout(String refreshToken) =>
      _api.postNoContent('/auth/logout', {'refreshToken': refreshToken});

  @override
  Future<void> requestPasswordReset(PasswordResetRequest request) =>
      _api.postNoContent('/auth/password-reset', request.toJson());

  @override
  Future<ResetGrant> verifyPasswordResetCode(PasswordResetVerifyRequest request) async {
    final json = await _api.postJson('/auth/password-reset/verify', request.toJson());
    try {
      return ResetGrant.fromJson(json);
    } on FormatException {
      throw const ProblemFailure(status: 200, type: ProblemType.unknown);
    }
  }

  @override
  Future<void> confirmPasswordReset(PasswordResetConfirmRequest request) =>
      _api.postNoContent('/auth/password-reset/confirm', request.toJson());

  // A 2xx body that breaks the contract becomes a ProblemFailure, so callers handle one failure type.
  // PT: Um corpo 2xx que quebra o contrato vira ProblemFailure, então quem chama trata um só tipo de falha.
  static AuthResponse _parse(int status, Map<String, Object?> json) {
    try {
      return AuthResponse.fromJson(json);
    } on FormatException {
      throw ProblemFailure(status: status, type: ProblemType.unknown);
    }
  }
}

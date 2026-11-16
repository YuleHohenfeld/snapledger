import 'dart:async';

import 'package:snapledger/core/api/token_response.dart';
import 'package:snapledger/features/auth/_shared/data/models/auth_response.dart';
import 'package:snapledger/features/auth/_shared/data/models/login_request.dart';
import 'package:snapledger/features/auth/_shared/data/models/register_request.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/profile/_shared/data/models/user_model.dart';

/// An [AuthRepository] that records requests and answers with [response], or throws [failure].
/// PT: Um [AuthRepository] que registra as requisições e responde com [response], ou lança [failure].
class FakeAuthRepository implements AuthRepository {
  AuthResponse response = fakeAuthResponse(1);

  /// Thrown instead of answering when set.
  /// PT: Lançada em vez da resposta quando definida.
  Exception? failure;

  /// Thrown by [logout] when set, so login can succeed while the revoke fails.
  /// PT: Lançada pelo [logout] quando definida, para o login dar certo enquanto o revoke falha.
  Exception? logoutFailure;

  /// When set, every call waits for it, so a test can act while the request is in flight.
  /// PT: Quando definido, toda chamada espera por ele, para o teste agir com a requisição em andamento.
  Completer<void>? gate;

  final List<LoginRequest> logins = [];
  final List<RegisterRequest> registers = [];
  final List<String> logouts = [];

  @override
  Future<AuthResponse> login(LoginRequest request) async {
    logins.add(request);
    return _answer();
  }

  @override
  Future<AuthResponse> register(RegisterRequest request) async {
    registers.add(request);
    return _answer();
  }

  @override
  Future<void> logout(String refreshToken) async {
    logouts.add(refreshToken);
    if (logoutFailure case final logoutFailure?) throw logoutFailure;
  }

  Future<AuthResponse> _answer() async {
    await gate?.future;
    if (failure case final failure?) throw failure;
    return response;
  }
}

/// An [AuthResponse] with obviously fake tokens (`fake-access-n`, `fake-refresh-n`).
/// PT: Um [AuthResponse] com tokens obviamente falsos (`fake-access-n`, `fake-refresh-n`).
AuthResponse fakeAuthResponse(int n) => AuthResponse(
  user: UserModel(
    id: '6f1c2a4e-8b0d-4c39-9a51-2f7e0d3b9c11',
    name: 'Ana Souza',
    email: 'ana@example.com',
    currency: 'BRL',
    createdAt: DateTime.utc(2026, 11, 10, 14, 3, 22),
  ),
  tokens: TokenResponse(
    accessToken: 'fake-access-$n',
    tokenType: 'Bearer',
    expiresIn: 900,
    refreshToken: 'fake-refresh-$n',
    refreshExpiresIn: 2592000,
  ),
);

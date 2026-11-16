import 'package:dio/dio.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/api/json_body.dart';
import 'package:snapledger/core/api/token_response.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/core/storage/secure_store.dart';

/// Calls `POST /auth/refresh` with a Dio that has no AuthInterceptor; concurrent callers share one call.
/// PT: Chama `POST /auth/refresh` com um Dio sem AuthInterceptor; chamadas concorrentes compartilham uma.
/// Notes: docs/code-notes/app-core.md#apisessionrefresher
final class ApiSessionRefresher implements SessionRefresher {
  ApiSessionRefresher({required this._refreshDio, required this._tokens});

  final Dio _refreshDio;
  final TokenStore _tokens;
  Future<RefreshOutcome>? _inFlight;

  @override
  Future<RefreshOutcome> refresh() =>
      _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<RefreshOutcome> _refresh() async {
    final epoch = _tokens.epoch;
    final String? refreshToken;
    try {
      refreshToken = await _tokens.readRefreshToken();
    } on SecureStoreException {
      // Storage temporarily unavailable (keychain locked): keep the session, try again later.
      // PT: Armazenamento indisponível no momento (keychain bloqueado): mantém a sessão, tenta depois.
      return const TemporaryFailure();
    }
    if (refreshToken == null) return _endSession(epoch);

    final Response<String> response;
    try {
      response = await _refreshDio.post<String>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
    } on DioException catch (error) {
      final answer = error.response;
      // Only a rejected refresh token ends the session; 500, timeouts and other 4xx may be temporary.
      // PT: Só um refresh token rejeitado encerra a sessão; 500, timeouts e outros 4xx podem ser temporários.
      if (answer != null &&
          answer.statusCode == 401 &&
          ProblemFailure.fromResponse(401, answer.data).type == ProblemType.invalidRefreshToken) {
        return _endSession(epoch);
      }
      return const TemporaryFailure();
    }

    final body = decodeJsonObject(response.data);
    if (body == null) return const TemporaryFailure();
    final TokenResponse pair;
    try {
      pair = TokenResponse.fromJson(body);
    } on FormatException {
      return const TemporaryFailure();
    }
    try {
      final saved = await _tokens.saveIfEpoch(
        epoch,
        accessToken: pair.accessToken,
        refreshToken: pair.refreshToken,
      );
      return saved ? Refreshed(pair.accessToken) : const TemporaryFailure();
    } on SecureStoreException {
      return const TemporaryFailure();
    }
  }

  // A moved epoch belongs to a newer sign-in or wipe: leave it alone and end nothing.
  // PT: Um epoch alterado pertence a um login ou wipe mais novo: não mexa nele e não encerre nada.
  Future<RefreshOutcome> _endSession(int epoch) async {
    if (_tokens.epoch != epoch) return const TemporaryFailure();
    try {
      await _tokens.clear();
    } on SecureStoreException {
      // Memory is clear, the epoch moved and the delete is pending: the session has ended anyway.
      // PT: A memória está limpa, o epoch mudou e o delete ficou pendente: a sessão terminou mesmo assim.
    }
    return const SessionEnded();
  }
}

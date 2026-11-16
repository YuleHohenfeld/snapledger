import 'package:dio/dio.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';

/// Attaches the Bearer token and, on `401 unauthorized`, refreshes once and retries once.
/// PT: Anexa o token Bearer e, em `401 unauthorized`, faz um refresh e tenta de novo uma vez.
/// Notes: docs/code-notes/app-core.md#authinterceptor
final class AuthInterceptor extends Interceptor {
  /// [dio] is the client this interceptor is attached to; [apiBase] is the only origin that gets a token.
  /// PT: [dio] é o cliente onde este interceptor está; [apiBase] é a única origem que recebe token.
  AuthInterceptor({
    required this._dio,
    required this._apiBase,
    required this._tokens,
    required this._refresher,
    required this._session,
  });

  static const _retriedKey = 'snapledger.retried';
  static const _sentTokenKey = 'snapledger.sentToken';
  static const _authorization = 'Authorization';

  final Dio _dio;
  final Uri _apiBase;
  final TokenStore _tokens;
  final SessionRefresher _refresher;
  final SessionNotifier _session;

  // Only the API's own non-auth endpoints get a token or a refresh; /auth/* is public (ADR 0005).
  // PT: Só os endpoints da própria API fora de auth recebem token ou refresh; /auth/* é público (ADR 0005).
  // Notes: docs/code-notes/app-core.md#protected-requests
  bool _isProtected(Uri uri) {
    if (uri.scheme != _apiBase.scheme ||
        uri.host != _apiBase.host ||
        uri.port != _apiBase.port) {
      return false;
    }
    final basePath = _apiBase.path.endsWith('/') ? _apiBase.path : '${_apiBase.path}/';
    if (!uri.path.startsWith(basePath)) return false;
    final relative = uri.path.substring(basePath.length);
    return relative != 'auth' && !relative.startsWith('auth/');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.remove(_authorization);
    options.extra.remove(_sentTokenKey);
    final token = _tokens.accessToken;
    if (token != null && _isProtected(options.uri)) {
      options.headers[_authorization] = 'Bearer $token';
      options.extra[_sentTokenKey] = token;
    }
    handler.next(options);
  }

  /// Refreshes on `401 unauthorized` from a protected request, then retries it once.
  /// PT: Faz refresh num `401 unauthorized` de uma requisição protegida e depois a repete uma vez.
  /// Notes: docs/code-notes/app-core.md#onerror
  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    if (!_isUnauthorized(err) || !_isProtected(request.uri)) {
      handler.next(err);
      return;
    }
    if (request.extra[_retriedKey] == true) {
      // A fresh token was rejected too: the session is gone; never a third request.
      // PT: Um token novo também foi rejeitado: a sessão acabou; nunca uma terceira requisição.
      await _session.wipe();
      handler.next(err);
      return;
    }

    // A different token in memory means another request refreshed meanwhile: retry without refreshing.
    // PT: Um token diferente em memória significa que outra requisição fez refresh: repete sem refresh.
    final current = _tokens.accessToken;
    if (current == null || current == request.extra[_sentTokenKey]) {
      switch (await _refresher.refresh()) {
        case Refreshed():
          break;
        case SessionEnded():
          // The refresher cleared the tokens: move the app to signed out (idempotent).
          // PT: O refresher apagou os tokens: leva o app para deslogado (idempotente).
          await _session.wipe();
          handler.next(err);
          return;
        case TemporaryFailure():
          handler.next(err);
          return;
      }
    }

    try {
      final retry = request.copyWith(extra: {...request.extra, _retriedKey: true});
      // `<String>`, like ApiClient: the body stays raw and ApiClient decodes it.
      // PT: `<String>`, como no ApiClient: o corpo fica bruto e o ApiClient o decodifica.
      handler.resolve(await _dio.fetch<String>(retry));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  static bool _isUnauthorized(DioException err) {
    final response = err.response;
    return response != null &&
        response.statusCode == 401 &&
        ProblemFailure.fromResponse(401, response.data).type == ProblemType.unauthorized;
  }
}

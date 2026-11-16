import 'package:dio/dio.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_session_refresher.dart';
import 'package:snapledger/core/api/auth_interceptor.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';

// Build order (lib/app): TokenStore -> buildSessionRefresher -> SessionNotifier -> buildApiClient.
// PT: Ordem de montagem (lib/app): TokenStore -> buildSessionRefresher -> SessionNotifier -> buildApiClient.
// Notes: docs/code-notes/app-core.md#apistack

/// Shared options for every Dio: `/api/v1` base, timeouts, JSON in and out, no redirects.
/// PT: Opções comuns a todo Dio: base `/api/v1`, timeouts, JSON na ida e na volta, sem redirects.
/// Notes: docs/code-notes/app-core.md#apistack
BaseOptions apiBaseOptions(AppConfig config) => BaseOptions(
  baseUrl: _apiBase(config),
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 20),
  contentType: Headers.jsonContentType,
  responseType: ResponseType.plain,
  followRedirects: false,
  headers: {Headers.acceptHeader: 'application/json, application/problem+json'},
);

/// The refresher with its own Dio, which never carries the AuthInterceptor (no recursion).
/// PT: O refresher com o próprio Dio, que nunca leva o AuthInterceptor (sem recursão).
SessionRefresher buildSessionRefresher(
  AppConfig config,
  TokenStore tokens, {
  HttpClientAdapter? adapter,
}) => ApiSessionRefresher(refreshDio: _dio(config, adapter), tokens: tokens);

/// The ApiClient whose Dio carries the AuthInterceptor; [adapter] replaces the network in tests.
/// PT: O ApiClient cujo Dio leva o AuthInterceptor; [adapter] substitui a rede nos testes.
ApiClient buildApiClient(
  AppConfig config, {
  required TokenStore tokens,
  required SessionRefresher refresher,
  required SessionNotifier session,
  HttpClientAdapter? adapter,
}) {
  final dio = _dio(config, adapter);
  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      apiBase: Uri.parse(_apiBase(config)),
      tokens: tokens,
      refresher: refresher,
      session: session,
    ),
  );
  return ApiClient(dio);
}

String _apiBase(AppConfig config) => '${config.apiBaseUrl}/api/v1';

// No LogInterceptor, ever: it would print tokens, passwords and personal data (D3).
// PT: Nenhum LogInterceptor, nunca: ele imprimiria tokens, senhas e dados pessoais (D3).
Dio _dio(AppConfig config, HttpClientAdapter? adapter) {
  final dio = Dio(apiBaseOptions(config));
  if (adapter != null) dio.httpClientAdapter = adapter;
  return dio;
}

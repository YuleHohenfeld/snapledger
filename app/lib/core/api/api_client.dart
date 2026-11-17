import 'package:dio/dio.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/api/json_body.dart';

/// The only door to the API for repositories; every failure leaves it as an [ApiFailure].
/// PT: A única porta para a API dos repositórios; toda falha sai daqui como [ApiFailure].
/// Notes: docs/code-notes/app-core.md#apiclient
final class ApiClient {
  /// Takes the Dio built by `buildApiClient` (api_stack.dart), already holding the interceptor.
  /// PT: Recebe o Dio montado pelo `buildApiClient` (api_stack.dart), já com o interceptor.
  const ApiClient(this._dio);

  final Dio _dio;

  /// GET a JSON object; [path] is relative to `/api/v1`.
  /// PT: GET de um objeto JSON; [path] é relativo a `/api/v1`.
  Future<Map<String, Object?>> getJson(String path, {Map<String, Object?>? query}) =>
      _jsonObject(() => _dio.get<String>(path, queryParameters: query));

  /// POST a JSON body and read a JSON object back.
  /// PT: POST de um corpo JSON e leitura de um objeto JSON de volta.
  Future<Map<String, Object?>> postJson(String path, Map<String, Object?> body) =>
      _jsonObject(() => _dio.post<String>(path, data: body));

  /// POST a JSON body to an endpoint that answers `204 No Content`.
  /// PT: POST de um corpo JSON para um endpoint que responde `204 No Content`.
  Future<void> postNoContent(String path, Map<String, Object?> body) async {
    await _send(() => _dio.post<String>(path, data: body));
  }

  // `<String>` keeps Dio from decoding: we decode, so a malformed body keeps its status.
  // PT: `<String>` impede o Dio de decodificar: nós decodificamos, então um corpo malformado mantém o status.
  Future<Map<String, Object?>> _jsonObject(Future<Response<String>> Function() call) async {
    final response = await _send(call);
    final body = decodeJsonObject(response.data);
    // A 2xx without the promised JSON object is a contract break: fail loudly, never return {}.
    // PT: Um 2xx sem o objeto JSON prometido quebra o contrato: falhe alto, nunca devolva {}.
    if (body == null) {
      throw ProblemFailure(status: response.statusCode ?? 0, type: ProblemType.unknown);
    }
    return body;
  }

  Future<Response<String>> _send(Future<Response<String>> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      final response = error.response;
      if (response == null) throw const NetworkFailure();
      throw ProblemFailure.fromResponse(response.statusCode ?? 0, response.data);
    }
  }
}

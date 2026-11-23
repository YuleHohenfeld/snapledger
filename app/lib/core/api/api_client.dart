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

  /// GET a JSON array of objects (a list endpoint); a 2xx with anything else is a [ProblemFailure].
  /// PT: GET de um array JSON de objetos (endpoint de lista); um 2xx com outra coisa é um [ProblemFailure].
  /// Notes: docs/code-notes/app-core.md#apiclient
  Future<List<Map<String, Object?>>> getJsonList(String path, {Map<String, Object?>? query}) async {
    final response = await _send(() => _dio.get<String>(path, queryParameters: query));
    final body = decodeJsonList(response.data);
    if (body == null) {
      throw ProblemFailure(status: response.statusCode ?? 0, type: ProblemType.unknown);
    }
    return body;
  }

  /// PUT a JSON body (full replacement) and read a JSON object back.
  /// PT: PUT de um corpo JSON (substituição completa) e leitura de um objeto JSON de volta.
  Future<Map<String, Object?>> putJson(String path, Map<String, Object?> body) =>
      _jsonObject(() => _dio.put<String>(path, data: body));

  /// PATCH a JSON body (partial change) and read a JSON object back.
  /// PT: PATCH de um corpo JSON (mudança parcial) e leitura de um objeto JSON de volta.
  Future<Map<String, Object?>> patchJson(String path, Map<String, Object?> body) =>
      _jsonObject(() => _dio.patch<String>(path, data: body));

  /// DELETE an endpoint whose success has no body (`204`).
  /// PT: DELETE de um endpoint cujo sucesso não tem corpo (`204`).
  Future<void> deleteNoContent(String path) async {
    await _send(() => _dio.delete<String>(path));
  }

  /// POST (with [body], or none) to an endpoint whose success has no body (`202` / `204`).
  /// PT: POST (com [body], ou sem) para um endpoint cujo sucesso não tem corpo (`202` / `204`).
  Future<void> postNoContent(String path, [Map<String, Object?>? body]) async {
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

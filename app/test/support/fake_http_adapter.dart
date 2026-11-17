import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Replaces the network under a real Dio: records every request and answers with [_answer].
/// PT: Substitui a rede sob um Dio real: registra toda requisição e responde com [_answer].
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this._answer);

  final Future<ResponseBody> Function(RequestOptions options) _answer;

  /// Every request that reached the network, in order.
  /// PT: Toda requisição que chegou à rede, em ordem.
  final List<RequestOptions> requests = [];

  /// How many requests were sent to [path] (as passed to Dio, relative to the base URL).
  /// PT: Quantas requisições foram enviadas para [path] (como passado ao Dio, relativo à URL base).
  int callsTo(String path) => requests.where((r) => r.path == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return _answer(options);
  }

  @override
  void close({bool force = false}) {}
}

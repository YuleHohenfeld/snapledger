import 'dart:convert';

import 'package:dio/dio.dart';

/// A response whose body is [body] encoded as JSON.
/// PT: Uma resposta cujo corpo é [body] codificado em JSON.
ResponseBody jsonBody(int status, Object? body, {String type = 'application/json'}) =>
    textBody(status, jsonEncode(body), type: type);

/// A response whose body is exactly [text] (for broken or non-JSON bodies).
/// PT: Uma resposta cujo corpo é exatamente [text] (para corpos quebrados ou que não são JSON).
ResponseBody textBody(int status, String text, {String type = 'application/json'}) =>
    ResponseBody.fromString(text, status, headers: {
      Headers.contentTypeHeader: [type],
    });

/// A contract ProblemDetail (`urn:snapledger:problem:<slug>`) as `application/problem+json`.
/// PT: Um ProblemDetail do contrato (`urn:snapledger:problem:<slug>`) como `application/problem+json`.
ResponseBody problemBody(int status, String slug) => jsonBody(
  status,
  {'type': 'urn:snapledger:problem:$slug', 'title': 'x', 'status': status},
  type: 'application/problem+json',
);

/// A contract TokenResponse with obviously fake tokens (`fake-access-n`, `fake-refresh-n`).
/// PT: Um TokenResponse do contrato com tokens obviamente falsos (`fake-access-n`, `fake-refresh-n`).
Map<String, Object?> fakeTokenJson(int n) => {
  'accessToken': 'fake-access-$n',
  'tokenType': 'Bearer',
  'expiresIn': 900,
  'refreshToken': 'fake-refresh-$n',
  'refreshExpiresIn': 2592000,
};

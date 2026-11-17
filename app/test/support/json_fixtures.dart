import 'dart:convert';

import 'package:dio/dio.dart';

/// A response whose body is [body] encoded as JSON.
/// PT: Uma resposta cujo corpo é [body] codificado em JSON.
ResponseBody jsonBody(int status, Object? body, {String type = 'application/json'}) =>
    textBody(status, jsonEncode(body), type: type);

/// A response whose body is exactly [text] (for broken or non-JSON bodies).
/// PT: Uma resposta cujo corpo é exatamente [text] (para corpos quebrados ou que não são JSON).
ResponseBody textBody(int status, String text, {String type = 'application/json'}) =>
    ResponseBody.fromString(
      text,
      status,
      headers: {
        Headers.contentTypeHeader: [type],
      },
    );

/// A contract ProblemDetail (`urn:snapledger:problem:<slug>`) as `application/problem+json`.
/// PT: Um ProblemDetail do contrato (`urn:snapledger:problem:<slug>`) como `application/problem+json`.
ResponseBody problemBody(int status, String slug) => jsonBody(status, {
  'type': 'urn:snapledger:problem:$slug',
  'title': 'x',
  'status': status,
}, type: 'application/problem+json');

/// A contract TokenResponse with obviously fake tokens (`fake-access-n`, `fake-refresh-n`).
/// PT: Um TokenResponse do contrato com tokens obviamente falsos (`fake-access-n`, `fake-refresh-n`).
Map<String, Object?> fakeTokenJson(int n) => {
  'accessToken': 'fake-access-$n',
  'tokenType': 'Bearer',
  'expiresIn': 900,
  'refreshToken': 'fake-refresh-$n',
  'refreshExpiresIn': 2592000,
};

/// A contract UserResponse for a made-up user.
/// PT: Um UserResponse do contrato para um usuário inventado.
Map<String, Object?> fakeUserJson() => {
  'id': '6f1c2a4e-8b0d-4c39-9a51-2f7e0d3b9c11',
  'name': 'Ana Souza',
  'email': 'ana@example.com',
  'currency': 'BRL',
  'createdAt': '2026-11-10T14:03:22Z',
};

/// The register / login success body: `{user, tokens}` with [fakeTokenJson] number [n].
/// PT: O corpo de sucesso de cadastro / login: `{user, tokens}` com o [fakeTokenJson] número [n].
Map<String, Object?> fakeAuthJson(int n) => {'user': fakeUserJson(), 'tokens': fakeTokenJson(n)};

/// A `400 validation-error` ProblemDetail rejecting [fields] (server messages included, never shown).
/// PT: Um ProblemDetail `400 validation-error` rejeitando [fields] (com mensagens do servidor, nunca exibidas).
ResponseBody validationProblemBody(List<String> fields) => jsonBody(400, {
  'type': 'urn:snapledger:problem:validation-error',
  'title': 'Validation failed',
  'status': 400,
  'errors': [
    for (final field in fields) {'field': field, 'message': 'server text'},
  ],
}, type: 'application/problem+json');

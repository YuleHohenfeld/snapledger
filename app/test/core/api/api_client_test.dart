import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/api/api_stack.dart';
import 'package:snapledger/core/config/app_config.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/json_fixtures.dart';

void main() {
  late FakeHttpAdapter adapter;
  late ApiClient api;
  final config = AppConfig.parse('https://api.test/', isRelease: true);

  void setUpClient(Future<ResponseBody> Function(RequestOptions options) answer) {
    adapter = FakeHttpAdapter(answer);
    api = ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = adapter);
  }

  test('sends requests under /api/v1 and asks for JSON', () async {
    setUpClient((_) async => jsonBody(200, {'id': 'u1'}));

    final body = await api.getJson('/expenses', query: {'month': '2026-11'});

    expect(body, {'id': 'u1'});
    final request = adapter.requests.single;
    expect(request.uri.toString(), 'https://api.test/api/v1/expenses?month=2026-11');
    expect(request.headers[Headers.acceptHeader], contains('application/json'));
  });

  test('posts a JSON body and decodes the JSON answer', () async {
    setUpClient((_) async => jsonBody(201, {'ok': true}));

    final body = await api.postJson('/categories', {'name': 'Food'});

    expect(body, {'ok': true});
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.contentType, startsWith('application/json'));
    expect(request.data, {'name': 'Food'});
  });

  test('accepts 204 No Content', () async {
    setUpClient((_) async => ResponseBody.fromString('', 204));

    await expectLater(api.postNoContent('/auth/logout', {'refreshToken': 'fake-refresh-1'}),
        completes);
  });

  test('turns a problem+json answer into a typed ProblemFailure', () async {
    setUpClient((_) async => textBody(
          409,
          jsonEncode({'type': 'urn:snapledger:problem:email-already-registered', 'status': 409}),
          type: 'application/problem+json',
        ));

    await expectLater(
      api.postJson('/auth/register', {'email': 'ana@example.com'}),
      throwsA(isA<ProblemFailure>()
          .having((f) => f.status, 'status', 409)
          .having((f) => f.type, 'type', ProblemType.emailAlreadyRegistered)),
    );
  });

  test('keeps the status of an error without a ProblemDetail body', () async {
    setUpClient((_) async => textBody(403, '', type: 'text/plain'));

    await expectLater(
      api.getJson('/users/me'),
      throwsA(isA<ProblemFailure>()
          .having((f) => f.status, 'status', 403)
          .having((f) => f.type, 'type', ProblemType.unknown)),
    );
  });

  test('never follows a redirect: a 3xx is a ProblemFailure with that status', () async {
    expect(apiBaseOptions(config).followRedirects, isFalse);
    setUpClient((_) async => ResponseBody.fromString('', 302, headers: {
          HttpHeaders.locationHeader: ['https://elsewhere.test/collect'],
        }));

    await expectLater(
      api.getJson('/users/me'),
      throwsA(isA<ProblemFailure>()
          .having((f) => f.status, 'status', 302)
          .having((f) => f.type, 'type', ProblemType.unknown)),
    );
    expect(adapter.requests, hasLength(1));
  });

  test('turns "no response" into NetworkFailure', () async {
    setUpClient((options) async => throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
          error: const SocketException('offline'),
        ));

    await expectLater(api.getJson('/users/me'), throwsA(isA<NetworkFailure>()));
  });

  test('turns a timeout into NetworkFailure', () async {
    setUpClient((options) async => throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: options,
        ));

    await expectLater(api.getJson('/users/me'), throwsA(isA<NetworkFailure>()));
  });

  test('fails loudly on a 2xx whose body is not a JSON object', () async {
    for (final body in ['', '{broken', '[1,2]', '<html>captive portal</html>']) {
      setUpClient((_) async => textBody(200, body));

      await expectLater(
        api.getJson('/users/me'),
        throwsA(isA<ProblemFailure>()
            .having((f) => f.status, 'status', 200)
            .having((f) => f.type, 'type', ProblemType.unknown)),
        reason: body,
      );
    }
  });

  group('lists', () {
    test('getJsonList decodes an array of objects, with the query', () async {
      setUpClient((_) async => jsonBody(200, [
            {'id': 'a'},
            {'id': 'b'},
          ]));

      final items = await api.getJsonList('/expenses', query: {'month': '2026-11'});

      expect(items, [
        {'id': 'a'},
        {'id': 'b'},
      ]);
      expect(adapter.requests.single.uri.toString(), 'https://api.test/api/v1/expenses?month=2026-11');
    });

    test('an empty array is a valid list', () async {
      setUpClient((_) async => jsonBody(200, <Object?>[]));

      expect(await api.getJsonList('/categories'), isEmpty);
    });

    test('fails loudly on a 2xx that is not an array of objects', () async {
      for (final body in ['', '{broken', '{"id":"a"}', '[1,2]', '[{"id":"a"}, 3]', '<html></html>']) {
        setUpClient((_) async => textBody(200, body));

        await expectLater(
          api.getJsonList('/categories'),
          throwsA(isA<ProblemFailure>()
              .having((f) => f.status, 'status', 200)
              .having((f) => f.type, 'type', ProblemType.unknown)),
          reason: body,
        );
      }
    });

    test('a problem answer to a list call is a typed failure', () async {
      setUpClient((_) async => problemBody(401, 'unauthorized'));

      await expectLater(
        api.getJsonList('/categories'),
        throwsA(isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.unauthorized)),
      );
    });
  });

  group('PUT, PATCH and DELETE', () {
    test('putJson sends the body with PUT and decodes the object', () async {
      setUpClient((_) async => jsonBody(200, {'ok': true}));

      final body = await api.putJson('/expenses/e1', {'amount': '12.50'});

      expect(body, {'ok': true});
      final request = adapter.requests.single;
      expect(request.method, 'PUT');
      expect(request.uri.toString(), 'https://api.test/api/v1/expenses/e1');
      expect(request.data, {'amount': '12.50'});
    });

    test('patchJson sends the body with PATCH and decodes the object', () async {
      setUpClient((_) async => jsonBody(200, {'ok': true}));

      final body = await api.patchJson('/categories/c1', {'name': 'Pets'});

      expect(body, {'ok': true});
      expect(adapter.requests.single.method, 'PATCH');
      expect(adapter.requests.single.data, {'name': 'Pets'});
    });

    test('putJson and patchJson fail loudly on a 2xx without a JSON object', () async {
      setUpClient((_) async => textBody(200, ''));

      await expectLater(api.putJson('/expenses/e1', {}), throwsA(isA<ProblemFailure>()));
      await expectLater(api.patchJson('/categories/c1', {}), throwsA(isA<ProblemFailure>()));
    });

    test('deleteNoContent accepts 204 and sends DELETE', () async {
      setUpClient((_) async => ResponseBody.fromString('', 204));

      await api.deleteNoContent('/categories/c1');

      expect(adapter.requests.single.method, 'DELETE');
      expect(adapter.requests.single.uri.path, '/api/v1/categories/c1');
    });

    test('deleteNoContent turns a 409 into a typed failure', () async {
      setUpClient((_) async => problemBody(409, 'category-in-use'));

      await expectLater(
        api.deleteNoContent('/categories/c1'),
        throwsA(isA<ProblemFailure>()
            .having((f) => f.status, 'status', 409)
            .having((f) => f.type, 'type', ProblemType.categoryInUse)),
      );
    });
  });
}

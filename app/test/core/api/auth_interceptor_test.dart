import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/api/api_stack.dart';
import 'package:snapledger/core/api/auth_interceptor.dart';
import 'package:snapledger/core/api/token_response.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/in_memory_secure_store.dart';
import '../../support/json_fixtures.dart';

const _expenses = '/expenses';
const _refresh = '/auth/refresh';

final _config = AppConfig.parse('https://api.test', isRelease: true);

/// The real stack (ApiClient + AuthInterceptor + ApiSessionRefresher) over a fake network.
/// PT: A pilha real (ApiClient + AuthInterceptor + ApiSessionRefresher) sobre uma rede falsa.
class _Stack {
  _Stack._(this.store, this.tokens, this.refresher, this.session, this.api, this.adapter);

  static Future<_Stack> signedIn(Future<ResponseBody> Function(RequestOptions o) answer) async {
    final store = InMemorySecureStore();
    final tokens = TokenStore(store);
    final adapter = FakeHttpAdapter(answer);
    final refresher = buildSessionRefresher(_config, tokens, adapter: adapter);
    final session = SessionNotifier(tokens: tokens, refresher: refresher);
    await session.signIn(TokenResponse.fromJson(fakeTokenJson(1)));
    final api = buildApiClient(
      _config,
      tokens: tokens,
      refresher: refresher,
      session: session,
      adapter: adapter,
    );
    return _Stack._(store, tokens, refresher, session, api, adapter);
  }

  final InMemorySecureStore store;
  final TokenStore tokens;
  final SessionRefresher refresher;
  final SessionNotifier session;
  final ApiClient api;
  final FakeHttpAdapter adapter;

  Future<void> expectStillSignedIn() async {
    expect(session.status, SessionStatus.signedIn);
    expect(tokens.accessToken, 'fake-access-1');
    expect(await tokens.readRefreshToken(), 'fake-refresh-1');
  }

  Future<void> expectWiped() async {
    expect(session.status, SessionStatus.signedOut);
    expect(tokens.accessToken, isNull);
    expect(await tokens.readRefreshToken(), isNull);
    expect(store.values, isEmpty);
  }
}

String? _bearer(RequestOptions o) => o.headers['Authorization'] as String?;

final _unauthorized = throwsA(
  isA<ProblemFailure>()
      .having((f) => f.status, 'status', 401)
      .having((f) => f.type, 'type', ProblemType.unauthorized),
);

void main() {
  test('concurrent 401s trigger exactly one refresh and each request is retried once', () async {
    // The refresh answers only after the three original requests were sent.
    // PT: O refresh só responde depois que as três requisições originais foram enviadas.
    final threeSent = Completer<void>();
    late _Stack stack;
    stack = await _Stack.signedIn((o) async {
      if (o.path == _refresh) {
        await threeSent.future;
        return jsonBody(200, fakeTokenJson(2));
      }
      if (stack.adapter.callsTo(_expenses) == 3 && !threeSent.isCompleted) threeSent.complete();
      return _bearer(o) == 'Bearer fake-access-2'
          ? jsonBody(200, {'ok': true})
          : problemBody(401, 'unauthorized');
    });

    final results = await Future.wait([for (var i = 0; i < 3; i++) stack.api.getJson(_expenses)]);

    expect(results, everyElement({'ok': true}));
    expect(stack.adapter.callsTo(_refresh), 1);
    // 3 originals + 3 retries. PT: 3 originais + 3 novas tentativas.
    expect(stack.adapter.callsTo(_expenses), 6);
    expect(stack.tokens.accessToken, 'fake-access-2');
    expect(await stack.tokens.readRefreshToken(), 'fake-refresh-2');
    expect(stack.session.status, SessionStatus.signedIn);
  });

  test('persists the rotated refresh token before the retry is sent', () async {
    String? storedWhenRetried;
    late _Stack stack;
    stack = await _Stack.signedIn((o) async {
      if (o.path == _refresh) return jsonBody(200, fakeTokenJson(2));
      if (_bearer(o) == 'Bearer fake-access-2') {
        storedWhenRetried = stack.store.values[TokenStore.refreshTokenKey];
        return jsonBody(200, {'ok': true});
      }
      return problemBody(401, 'unauthorized');
    });

    await stack.api.getJson(_expenses);

    expect(storedWhenRetried, 'fake-refresh-2');
  });

  test('sends the stored refresh token to /auth/refresh without an Authorization header', () async {
    final stack = await _Stack.signedIn((o) async => o.path == _refresh
        ? jsonBody(200, fakeTokenJson(2))
        : _bearer(o) == 'Bearer fake-access-2'
            ? jsonBody(200, {'ok': true})
            : problemBody(401, 'unauthorized'));

    await stack.api.getJson(_expenses);

    final refresh = stack.adapter.requests.singleWhere((r) => r.path == _refresh);
    expect(refresh.data, {'refreshToken': 'fake-refresh-1'});
    expect(refresh.headers.containsKey('Authorization'), isFalse);
  });

  test('wipes the session when the refresh token is rejected', () async {
    final stack = await _Stack.signedIn((o) async => o.path == _refresh
        ? problemBody(401, 'invalid-refresh-token')
        : problemBody(401, 'unauthorized'));

    await expectLater(stack.api.getJson(_expenses), _unauthorized);

    await stack.expectWiped();
    expect(stack.adapter.callsTo(_expenses), 1);
  });

  test('wipes when the retried request is rejected again, without a third request', () async {
    final stack = await _Stack.signedIn((o) async => o.path == _refresh
        ? jsonBody(200, fakeTokenJson(2))
        : problemBody(401, 'unauthorized'));

    await expectLater(stack.api.getJson(_expenses), _unauthorized);

    expect(stack.adapter.callsTo(_expenses), 2);
    expect(stack.adapter.callsTo(_refresh), 1);
    await stack.expectWiped();
  });

  group('keeps the session when the refresh fails for a reason that may be temporary:', () {
    final failures = <String, Future<ResponseBody> Function(RequestOptions o)>{
      '500 internal-error': (_) async => problemBody(500, 'internal-error'),
      '400 validation-error': (_) async => problemBody(400, 'validation-error'),
      '401 with another type': (_) async => problemBody(401, 'unauthorized'),
      '429 about:blank': (_) async => jsonBody(429, {'type': 'about:blank', 'status': 429}),
      'timeout': (o) async =>
          throw DioException.receiveTimeout(timeout: const Duration(seconds: 1), requestOptions: o),
      'no network': (o) async => throw DioException.connectionError(
            requestOptions: o,
            reason: 'offline',
            error: const SocketException('offline'),
          ),
      'malformed 200 body': (_) async => textBody(200, '{broken'),
      '200 without a refresh token': (_) async =>
          jsonBody(200, {...fakeTokenJson(2)}..remove('refreshToken')),
    };

    for (final entry in failures.entries) {
      test(entry.key, () async {
        final stack = await _Stack.signedIn((o) async =>
            o.path == _refresh ? entry.value(o) : problemBody(401, 'unauthorized'));

        await expectLater(stack.api.getJson(_expenses), _unauthorized);

        await stack.expectStillSignedIn();
        expect(stack.adapter.callsTo(_expenses), 1);
      });
    }
  });

  test('never refreshes on a 401 from /auth/*', () async {
    final stack = await _Stack.signedIn((o) async => o.path == '/auth/login'
        ? problemBody(401, 'invalid-credentials')
        : problemBody(401, 'unauthorized'));

    await expectLater(
      stack.api.postJson('/auth/login', {'email': 'ana@example.com', 'password': 'fake-password'}),
      throwsA(isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.invalidCredentials)),
    );
    await expectLater(
      stack.api.postNoContent('/auth/logout', {'refreshToken': 'fake-refresh-1'}),
      _unauthorized,
    );

    expect(stack.adapter.callsTo(_refresh), 0);
    await stack.expectStillSignedIn();
  });

  test('attaches the Bearer token everywhere except /auth/*', () async {
    final stack = await _Stack.signedIn((o) async => jsonBody(200, {'ok': true}));

    await stack.api.getJson('/users/me');
    await stack.api.postJson('/auth/login', {'email': 'ana@example.com'});

    final byPath = {for (final r in stack.adapter.requests) r.path: r};
    expect(_bearer(byPath['/users/me']!), 'Bearer fake-access-1');
    expect(byPath['/auth/login']!.headers.containsKey('Authorization'), isFalse);
  });

  test('removes an Authorization header a caller put on an /auth/* request', () async {
    final stack = await _Stack.signedIn((o) async => jsonBody(200, {'ok': true}));
    final dio = Dio(apiBaseOptions(_config))..httpClientAdapter = stack.adapter;
    dio.interceptors.add(AuthInterceptor(
      dio: dio,
      apiBase: Uri.parse('https://api.test/api/v1'),
      tokens: stack.tokens,
      refresher: stack.refresher,
      session: stack.session,
    ));

    await dio.post<String>(
      '/auth/login',
      data: {'email': 'ana@example.com'},
      options: Options(headers: {'Authorization': 'Bearer stale'}),
    );

    expect(stack.adapter.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  group('absolute URLs get a token only on the API origin, outside /auth/*:', () {
    test('a foreign host gets no token and its 401 never refreshes', () async {
      final stack = await _Stack.signedIn((o) async => problemBody(401, 'unauthorized'));

      await expectLater(stack.api.getJson('https://evil.test/api/v1/users/me'), _unauthorized);

      expect(_bearer(stack.adapter.requests.single), isNull);
      expect(stack.adapter.callsTo(_refresh), 0);
      await stack.expectStillSignedIn();
    });

    test('another scheme, port or path outside /api/v1 gets no token', () async {
      final stack = await _Stack.signedIn((o) async => jsonBody(200, {'ok': true}));

      for (final url in [
        'http://api.test/api/v1/users/me',
        'https://api.test:8443/api/v1/users/me',
        'https://api.test/other/users/me',
        'https://api.test/api/v1x/users/me',
      ]) {
        await stack.api.getJson(url);
      }

      expect(stack.adapter.requests.map(_bearer), everyElement(isNull));
    });

    test("the API's own absolute /auth/login gets no token; /users/me does", () async {
      final stack = await _Stack.signedIn((o) async => jsonBody(200, {'ok': true}));

      await stack.api.postJson('https://api.test/api/v1/auth/login', {'email': 'ana@example.com'});
      await stack.api.getJson('https://api.test/api/v1/users/me');

      final byPath = {for (final r in stack.adapter.requests) r.uri.path: r};
      expect(_bearer(byPath['/api/v1/auth/login']!), isNull);
      expect(_bearer(byPath['/api/v1/users/me']!), 'Bearer fake-access-1');
    });
  });

  test('retries without refreshing when the request was sent with an older token', () async {
    late _Stack stack;
    stack = await _Stack.signedIn((o) async {
      if (_bearer(o) == 'Bearer fake-access-2') return jsonBody(200, {'ok': true});
      // Another request rotated the tokens while this one was in flight.
      // PT: Outra requisição rotacionou os tokens enquanto esta estava em voo.
      await stack.tokens.save(accessToken: 'fake-access-2', refreshToken: 'fake-refresh-2');
      return problemBody(401, 'unauthorized');
    });

    expect(await stack.api.getJson(_expenses), {'ok': true});

    expect(stack.adapter.callsTo(_refresh), 0);
    expect(stack.adapter.callsTo(_expenses), 2);
  });

  test('stays signed out when the session is wiped while a refresh is in flight', () async {
    late _Stack stack;
    stack = await _Stack.signedIn((o) async {
      if (o.path != _refresh) return problemBody(401, 'unauthorized');
      // The user signs out meanwhile. PT: O usuário sai nesse meio-tempo.
      await stack.session.wipe();
      return jsonBody(200, fakeTokenJson(2));
    });

    await expectLater(stack.api.getJson(_expenses), _unauthorized);

    await stack.expectWiped();
    expect(stack.adapter.callsTo(_expenses), 1);
  });

  test('passes every non-401 error through untouched', () async {
    final stack = await _Stack.signedIn((o) async => problemBody(404, 'not-found'));

    await expectLater(
      stack.api.getJson('/expenses/123'),
      throwsA(isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.notFound)),
    );

    expect(stack.adapter.callsTo(_refresh), 0);
    await stack.expectStillSignedIn();
  });

  test('never prints a token or a password', () async {
    final printed = <String>[];
    await runZoned(
      () async {
        final stack = await _Stack.signedIn((o) async {
          if (o.path == _refresh) return jsonBody(200, fakeTokenJson(2));
          if (o.path == '/auth/login') return problemBody(401, 'invalid-credentials');
          return _bearer(o) == 'Bearer fake-access-2'
              ? problemBody(500, 'internal-error')
              : problemBody(401, 'unauthorized');
        });
        final failures = <Object>[];
        for (final call in [
          () => stack.api.getJson(_expenses),
          () => stack.api.postJson('/auth/login', {'email': 'a@b.c', 'password': 'fake-password'}),
        ]) {
          try {
            await call();
          } on ApiFailure catch (failure) {
            failures.add(failure);
          }
        }
        // Whatever a caller might print must be safe too.
        // PT: O que quem chama talvez imprima também precisa ser seguro.
        failures
          ..add(TokenResponse.fromJson(fakeTokenJson(3)))
          ..add(const Refreshed('fake-access-3'))
          ..forEach((f) => printed.add(f.toString()));
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );

    expect(printed, isNotEmpty);
    for (final line in printed) {
      expect(line, isNot(contains('fake-access')));
      expect(line, isNot(contains('fake-refresh')));
      expect(line, isNot(contains('fake-password')));
    }
  });
}

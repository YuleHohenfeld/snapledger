import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_stack.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/in_memory_secure_store.dart';
import '../../support/json_fixtures.dart';

final _refreshed2 = isA<Refreshed>().having((r) => r.accessToken, 'accessToken', 'fake-access-2');

void main() {
  late InMemorySecureStore store;
  late TokenStore tokens;
  late FakeHttpAdapter adapter;
  late SessionRefresher refresher;

  void build(Future<ResponseBody> Function(RequestOptions o) answer) {
    adapter = FakeHttpAdapter(answer);
    refresher = buildSessionRefresher(
      AppConfig.parse('https://api.test', isRelease: true),
      tokens,
      adapter: adapter,
    );
  }

  setUp(() {
    store = InMemorySecureStore();
    tokens = TokenStore(store);
  });

  test('a cold start exchanges the stored token for a new pair', () async {
    store.values[TokenStore.refreshTokenKey] = 'fake-refresh-1';
    build((_) async => jsonBody(200, fakeTokenJson(2)));

    expect(await refresher.refresh(), _refreshed2);

    expect(tokens.accessToken, 'fake-access-2');
    expect(store.values[TokenStore.refreshTokenKey], 'fake-refresh-2');
    expect(adapter.requests.single.uri.toString(), 'https://api.test/api/v1/auth/refresh');
  });

  test('without a stored token it ends the session and calls nothing', () async {
    build((_) async => jsonBody(200, fakeTokenJson(2)));
    final epoch = tokens.epoch;

    expect(await refresher.refresh(), isA<SessionEnded>());

    expect(tokens.epoch, isNot(epoch));
    expect(adapter.requests, isEmpty);
  });

  test('ends the session when the server rejects the refresh token', () async {
    store.values[TokenStore.refreshTokenKey] = 'fake-refresh-1';
    build((_) async => problemBody(401, 'invalid-refresh-token'));

    expect(await refresher.refresh(), isA<SessionEnded>());

    expect(store.values, isEmpty);
    expect(tokens.accessToken, isNull);
  });

  test('still reports SessionEnded when the storage delete fails', () async {
    store.values[TokenStore.refreshTokenKey] = 'fake-refresh-1';
    store.failDelete = true;
    build((_) async => problemBody(401, 'invalid-refresh-token'));

    expect(await refresher.refresh(), isA<SessionEnded>());

    expect(await tokens.readRefreshToken(), isNull);
  });

  test('concurrent callers share one call and get the same outcome', () async {
    store.values[TokenStore.refreshTokenKey] = 'fake-refresh-1';
    final gate = Completer<void>();
    build((_) async {
      await gate.future;
      return jsonBody(200, fakeTokenJson(2));
    });

    final calls = [refresher.refresh(), refresher.refresh(), refresher.refresh()];
    gate.complete();

    expect(await Future.wait(calls), everyElement(_refreshed2));
    expect(adapter.requests, hasLength(1));
  });

  test('starts a new call once the previous one finished', () async {
    store.values[TokenStore.refreshTokenKey] = 'fake-refresh-1';
    var n = 1;
    build((_) async => jsonBody(200, fakeTokenJson(++n)));

    expect(await refresher.refresh(), _refreshed2);
    expect(
      await refresher.refresh(),
      isA<Refreshed>().having((r) => r.accessToken, 'accessToken', 'fake-access-3'),
    );
    expect(adapter.requests, hasLength(2));
  });

  test('keeps the session when the new pair cannot be saved', () async {
    store.values[TokenStore.refreshTokenKey] = 'fake-refresh-1';
    store.failWrite = true;
    final epoch = tokens.epoch;
    build((_) async => jsonBody(200, fakeTokenJson(2)));

    expect(await refresher.refresh(), isA<TemporaryFailure>());

    expect(tokens.epoch, epoch);
    expect(tokens.accessToken, isNull);
  });

  test('keeps the session when the storage is temporarily unreadable', () async {
    store.values[TokenStore.refreshTokenKey] = 'fake-refresh-1';
    store.failRead = true;
    final epoch = tokens.epoch;
    build((_) async => jsonBody(200, fakeTokenJson(2)));

    expect(await refresher.refresh(), isA<TemporaryFailure>());

    expect(tokens.epoch, epoch);
    expect(adapter.requests, isEmpty);
  });

  test('a rejection that arrives after a new sign-in does not end the new session', () async {
    store.values[TokenStore.refreshTokenKey] = 'fake-refresh-1';
    build((_) async {
      // Sign out and sign in again while the old refresh is in flight.
      // PT: Sai e entra de novo enquanto o refresh antigo está em voo.
      await tokens.clear();
      await tokens.save(accessToken: 'fake-access-9', refreshToken: 'fake-refresh-9');
      return problemBody(401, 'invalid-refresh-token');
    });

    expect(await refresher.refresh(), isA<TemporaryFailure>());

    expect(tokens.accessToken, 'fake-access-9');
    expect(store.values[TokenStore.refreshTokenKey], 'fake-refresh-9');
  });

  group('a sign-in while the refresh is in flight wins:', () {
    final answers = <String, ResponseBody Function()>{
      'a rejection does not clear it': () => problemBody(401, 'invalid-refresh-token'),
      'an old 200 does not overwrite it': () => jsonBody(200, fakeTokenJson(2)),
    };

    for (final entry in answers.entries) {
      test(entry.key, () async {
        store.values[TokenStore.refreshTokenKey] = 'fake-refresh-1';
        build((_) async {
          // No clear: a direct sign-in (save) must move the epoch on its own.
          // PT: Sem clear: um login direto (save) precisa mover o epoch sozinho.
          await tokens.save(accessToken: 'fake-access-9', refreshToken: 'fake-refresh-9');
          return entry.value();
        });

        expect(await refresher.refresh(), isA<TemporaryFailure>());

        expect(tokens.accessToken, 'fake-access-9');
        expect(store.values[TokenStore.refreshTokenKey], 'fake-refresh-9');
      });
    }
  });

  test('Refreshed never prints its token', () {
    expect(const Refreshed('fake-access-2').toString(), isNot(contains('fake-access')));
  });
}

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/api/token_response.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/core/storage/secure_store.dart';

import '../../support/fake_session_refresher.dart';
import '../../support/in_memory_secure_store.dart';

const _pair = TokenResponse(
  accessToken: 'fake-access-1',
  tokenType: 'Bearer',
  expiresIn: 900,
  refreshToken: 'fake-refresh-1',
  refreshExpiresIn: 2592000,
);

void main() {
  late InMemorySecureStore store;
  late TokenStore tokens;
  late FakeSessionRefresher refresher;
  late SessionNotifier session;
  late List<(SessionStatus, bool)> notified;

  setUp(() {
    store = InMemorySecureStore();
    tokens = TokenStore(store);
    refresher = FakeSessionRefresher(() async => const TemporaryFailure());
    session = SessionNotifier(tokens: tokens, refresher: refresher);
    notified = [];
    session.addListener(() => notified.add((session.status, session.restoreFailed)));
  });

  tearDown(() => session.dispose());

  test('starts unknown', () {
    expect(session.status, SessionStatus.unknown);
    expect(session.restoreFailed, isFalse);
  });

  group('restore', () {
    test('signs in when the refresh succeeds', () async {
      refresher.onRefresh = () async {
        await tokens.save(accessToken: 'fake-access-2', refreshToken: 'fake-refresh-2');
        return const Refreshed('fake-access-2');
      };

      await session.restore();

      expect(session.status, SessionStatus.signedIn);
      expect(notified, [(SessionStatus.signedIn, false)]);
    });

    test('signs out when the refresher ended the session', () async {
      // ApiSessionRefresher clears the tokens before it reports SessionEnded.
      // PT: O ApiSessionRefresher apaga os tokens antes de informar SessionEnded.
      refresher.onRefresh = () async {
        await tokens.clear();
        return const SessionEnded();
      };

      await session.restore();

      expect(session.status, SessionStatus.signedOut);
      expect(session.restoreFailed, isFalse);
    });

    test('stays unknown with restoreFailed and keeps the token on a temporary failure', () async {
      store.values[TokenStore.refreshTokenKey] = 'fake-refresh-1';

      await session.restore();

      expect(session.status, SessionStatus.unknown);
      expect(session.restoreFailed, isTrue);
      expect(await tokens.readRefreshToken(), 'fake-refresh-1');
    });

    test('a retry after a failure clears the flag and can sign in', () async {
      await session.restore();
      refresher.onRefresh = () async => const Refreshed('fake-access-2');

      await session.restore();

      expect(session.status, SessionStatus.signedIn);
      expect(session.restoreFailed, isFalse);
      expect(notified, [
        (SessionStatus.unknown, true),
        (SessionStatus.unknown, false),
        (SessionStatus.signedIn, false),
      ]);
    });

    test('calls while one is in flight share it: one refresh', () async {
      final gate = Completer<RefreshOutcome>();
      refresher.onRefresh = () => gate.future;

      final first = session.restore();
      final second = session.restore();
      gate.complete(const Refreshed('fake-access-2'));
      await Future.wait([first, second]);

      expect(refresher.calls, 1);
      expect(session.status, SessionStatus.signedIn);
    });

    test('does nothing once the state is known', () async {
      await session.signIn(_pair);

      await session.restore();

      expect(refresher.calls, 0);
      expect(session.status, SessionStatus.signedIn);
    });

    group('a sign-in during the cold-start refresh is not undone by an outcome of', () {
      for (final outcome in const <RefreshOutcome>[SessionEnded(), TemporaryFailure()]) {
        test('$outcome', () async {
          refresher.onRefresh = () async {
            await session.signIn(_pair);
            return outcome;
          };

          await session.restore();

          expect(session.status, SessionStatus.signedIn);
          expect(session.restoreFailed, isFalse);
          expect(tokens.accessToken, 'fake-access-1');
        });
      }
    });

    test('a wipe during the cold-start refresh stays signed out', () async {
      refresher.onRefresh = () async {
        await session.wipe();
        return const TemporaryFailure();
      };

      await session.restore();

      expect(session.status, SessionStatus.signedOut);
      expect(session.restoreFailed, isFalse);
    });
  });

  group('signIn', () {
    test('persists the pair, then signs in', () async {
      await session.signIn(_pair);

      expect(await tokens.readRefreshToken(), 'fake-refresh-1');
      expect(tokens.accessToken, 'fake-access-1');
      expect(session.status, SessionStatus.signedIn);
    });

    test('stays out and throws when the pair cannot be saved', () async {
      store.failWrite = true;

      await expectLater(session.signIn(_pair), throwsA(isA<SecureStoreException>()));
      expect(session.status, SessionStatus.unknown);
      expect(tokens.accessToken, isNull);
    });
  });

  group('wipe', () {
    test('forgets the tokens and signs out', () async {
      await session.signIn(_pair);

      await session.wipe();

      expect(session.status, SessionStatus.signedOut);
      expect(tokens.accessToken, isNull);
      expect(await tokens.readRefreshToken(), isNull);
    });

    test('signs out without throwing even when the storage delete fails', () async {
      await session.signIn(_pair);
      store.failDelete = true;

      await session.wipe();

      expect(session.status, SessionStatus.signedOut);
      expect(tokens.accessToken, isNull);
      expect(await tokens.readRefreshToken(), isNull);
    });
  });

  group('signOut', () {
    test('revokes with the stored refresh token, then wipes', () async {
      await session.signIn(_pair);
      String? revoked;

      await session.signOut(revoke: (refreshToken) async => revoked = refreshToken);

      expect(revoked, 'fake-refresh-1');
      expect(session.status, SessionStatus.signedOut);
      expect(await tokens.readRefreshToken(), isNull);
    });

    test('wipes even when the revoke call fails', () async {
      await session.signIn(_pair);

      await session.signOut(revoke: (_) async => throw const NetworkFailure());

      expect(session.status, SessionStatus.signedOut);
      expect(await tokens.readRefreshToken(), isNull);
    });

    test('waits at most 5 s for a revoke call that never answers, then wipes', () {
      fakeAsync((async) {
        unawaited(session.signIn(_pair));
        async.flushMicrotasks();
        var done = false;

        unawaited(
          session.signOut(revoke: (_) => Completer<void>().future).then((_) => done = true),
        );
        async.elapse(const Duration(milliseconds: 4999));

        expect(done, isFalse);
        expect(session.status, SessionStatus.signedIn);

        async.elapse(const Duration(milliseconds: 1));

        expect(done, isTrue);
        expect(session.status, SessionStatus.signedOut);
        expect(store.values, isEmpty);
      });
    });

    test('skips the revoke call when no token is stored', () async {
      var revokeCalls = 0;

      await session.signOut(revoke: (_) async => revokeCalls++);

      expect(revokeCalls, 0);
      expect(session.status, SessionStatus.signedOut);
    });
  });

  test('never notifies after dispose', () async {
    final gate = Completer<RefreshOutcome>();
    refresher.onRefresh = () => gate.future;
    final local = SessionNotifier(tokens: tokens, refresher: refresher);
    final restoring = local.restore();
    local.dispose();

    gate.complete(const Refreshed('fake-access-2'));
    await expectLater(restoring, completes);
  });
}

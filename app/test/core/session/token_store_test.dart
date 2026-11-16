import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/core/storage/secure_store.dart';

import '../../support/in_memory_secure_store.dart';

void main() {
  late InMemorySecureStore store;
  late TokenStore tokens;

  setUp(() {
    store = InMemorySecureStore();
    tokens = TokenStore(store);
  });

  test('persists only the refresh token; the access token stays in memory', () async {
    await tokens.save(accessToken: 'fake-access-1', refreshToken: 'fake-refresh-1');

    expect(store.values, {TokenStore.refreshTokenKey: 'fake-refresh-1'});
    expect(tokens.accessToken, 'fake-access-1');
    expect(await tokens.readRefreshToken(), 'fake-refresh-1');
  });

  test('a cold start has no access token until the first refresh', () async {
    store.values[TokenStore.refreshTokenKey] = 'fake-refresh-1';

    expect(TokenStore(store).accessToken, isNull);
  });

  test('does not expose the access token when persisting fails', () async {
    store.failWrite = true;

    await expectLater(
      tokens.save(accessToken: 'fake-access-1', refreshToken: 'fake-refresh-1'),
      throwsA(isA<SecureStoreException>()),
    );
    expect(tokens.accessToken, isNull);
  });

  test('persists the refresh token before the access token becomes visible', () async {
    String? visibleDuringWrite = 'not checked';
    store.beforeWrite = () async => visibleDuringWrite = tokens.accessToken;

    await tokens.save(accessToken: 'fake-access-1', refreshToken: 'fake-refresh-1');

    expect(visibleDuringWrite, isNull);
  });

  test('a save starts a new session: it moves the epoch', () async {
    final before = tokens.epoch;

    await tokens.save(accessToken: 'fake-access-1', refreshToken: 'fake-refresh-1');

    expect(tokens.epoch, isNot(before));
  });

  test('clear forgets both tokens and moves the epoch', () async {
    await tokens.save(accessToken: 'fake-access-1', refreshToken: 'fake-refresh-1');
    final before = tokens.epoch;

    await tokens.clear();

    expect(tokens.accessToken, isNull);
    expect(await tokens.readRefreshToken(), isNull);
    expect(tokens.epoch, before + 1);
  });

  group('when the delete of a clear fails', () {
    setUp(() async {
      await tokens.save(accessToken: 'fake-access-1', refreshToken: 'fake-refresh-1');
      store.failDelete = true;
      await expectLater(tokens.clear(), throwsA(isA<SecureStoreException>()));
    });

    test('memory is clear and the old token is never read back', () async {
      expect(tokens.accessToken, isNull);
      expect(store.values, isNotEmpty);
      expect(await tokens.readRefreshToken(), isNull);
    });

    test('the next read retries the delete', () async {
      store.failDelete = false;

      expect(await tokens.readRefreshToken(), isNull);

      expect(store.values, isEmpty);
    });

    test('a later save stores the new token and reads work again', () async {
      await tokens.save(accessToken: 'fake-access-2', refreshToken: 'fake-refresh-2');

      expect(await tokens.readRefreshToken(), 'fake-refresh-2');
    });

    test('a failed save keeps the old token hidden', () async {
      store.failWrite = true;

      await expectLater(
        tokens.save(accessToken: 'fake-access-2', refreshToken: 'fake-refresh-2'),
        throwsA(isA<SecureStoreException>()),
      );

      expect(await tokens.readRefreshToken(), isNull);
    });
  });

  group('saveIfEpoch', () {
    test('saves when nothing was cleared since the epoch was read', () async {
      final saved = await tokens.saveIfEpoch(tokens.epoch,
          accessToken: 'fake-access-2', refreshToken: 'fake-refresh-2');

      expect(saved, isTrue);
      expect(tokens.accessToken, 'fake-access-2');
      expect(await tokens.readRefreshToken(), 'fake-refresh-2');
    });

    test('refuses after a clear', () async {
      final epoch = tokens.epoch;
      await tokens.clear();

      final saved = await tokens.saveIfEpoch(epoch,
          accessToken: 'fake-access-2', refreshToken: 'fake-refresh-2');

      expect(saved, isFalse);
      expect(tokens.accessToken, isNull);
      expect(await tokens.readRefreshToken(), isNull);
    });

    test('never resurrects the session when a clear runs during the write', () async {
      final epoch = tokens.epoch;
      store.beforeWrite = () async {
        store.beforeWrite = null;
        await tokens.clear();
      };

      final saved = await tokens.saveIfEpoch(epoch,
          accessToken: 'fake-access-2', refreshToken: 'fake-refresh-2');

      expect(saved, isFalse);
      expect(tokens.accessToken, isNull);
      expect(await tokens.readRefreshToken(), isNull);
    });

    test('never deletes a sign-in that wrote after it', () async {
      final epoch = tokens.epoch;
      store.afterWrite = () async {
        store.afterWrite = null;
        // A sign-in writes right after this write landed, before saveIfEpoch checks the epoch.
        // PT: Um login escreve logo depois que esta escrita terminou, antes de o saveIfEpoch checar o epoch.
        await tokens.save(accessToken: 'fake-access-9', refreshToken: 'fake-refresh-9');
      };

      final saved = await tokens.saveIfEpoch(epoch,
          accessToken: 'fake-access-2', refreshToken: 'fake-refresh-2');

      expect(saved, isFalse);
      expect(tokens.accessToken, 'fake-access-9');
      expect(await tokens.readRefreshToken(), 'fake-refresh-9');
    });
  });
}

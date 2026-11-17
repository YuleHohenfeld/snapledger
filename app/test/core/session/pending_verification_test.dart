import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_session_refresher.dart';

void main() {
  late SessionNotifier session;
  late PendingVerification pending;

  setUp(() {
    session = inMemorySession().session;
    pending = PendingVerification(session: session);
  });

  tearDown(() {
    pending.dispose();
    session.dispose();
  });

  test('starts not pending; begin and clear flip it and notify once each', () {
    var notified = 0;
    pending.addListener(() => notified++);

    expect(pending.isPending, isFalse);
    pending.begin();
    pending.begin();
    expect(pending.isPending, isTrue);
    pending.clear();
    pending.clear();

    expect(pending.isPending, isFalse);
    expect(notified, 2);
  });

  test('stays pending when the session signs in', () async {
    pending.begin();

    await session.signIn(fakeAuthResponse(1).tokens);

    expect(pending.isPending, isTrue);
  });

  test('clears itself when the session ends', () async {
    await session.signIn(fakeAuthResponse(1).tokens);
    pending.begin();

    await session.wipe();

    expect(pending.isPending, isFalse);
  });

  test('stops listening to the session after dispose', () async {
    final local = PendingVerification(session: session)..dispose();

    await session.signIn(fakeAuthResponse(1).tokens);
    await session.wipe();

    expect(local.isPending, isFalse);
  });
}

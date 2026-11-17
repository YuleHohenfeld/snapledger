import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/verify_email/application/viewmodel/verify_email_view_model.dart';

import '../../../../../support/fake_email_verification_repository.dart';
import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/fake_user_repository.dart';

void main() {
  late FakeUserRepository users;
  late FakeEmailVerificationRepository verification;
  late SessionNotifier session;
  late PendingVerification pending;
  late VerifyEmailViewModel viewModel;

  const tooMany = ProblemFailure(status: 429, type: ProblemType.tooManyRequests);
  const invalidCode = ProblemFailure(status: 400, type: ProblemType.invalidCode);

  VerifyEmailViewModel build() =>
      VerifyEmailViewModel(users: users, verification: verification, pending: pending);

  setUp(() {
    users = FakeUserRepository();
    verification = FakeEmailVerificationRepository();
    session = inMemorySession().session;
    pending = PendingVerification(session: session);
    viewModel = build();
  });

  tearDown(() {
    viewModel.dispose();
    pending.dispose();
    session.dispose();
  });

  test('starts loading', () {
    expect(viewModel.state, isA<VerifyEmailLoading>());
  });

  group('opened from the profile', () {
    test('loads the email and sends a code', () async {
      await viewModel.start();

      expect(viewModel.state, isA<VerifyEmailReady>().having((s) => s.email, 'email', 'ana@example.com'));
      expect(verification.sends, 1);
      expect(viewModel.afterRegister, isFalse);
      expect(viewModel.cooldownSeconds, 60);
    });

    test('a 429 on the send shows the failure and still waits', () async {
      verification.sendFailure = tooMany;

      await viewModel.start();

      expect(viewModel.state, isA<VerifyEmailReady>().having((s) => s.failure, 'failure', tooMany));
      expect(viewModel.cooldownSeconds, 60);
    });
  });

  group('opened right after register', () {
    test('does not send another code, only starts the cooldown', () async {
      pending.begin();
      final local = build();

      await local.start();

      expect(local.afterRegister, isTrue);
      expect(verification.sends, 0);
      expect(local.cooldownSeconds, 60);
      expect(local.state, isA<VerifyEmailReady>());
      local.dispose();
    });
  });

  test('a load failure can be retried', () async {
    users.failure = const NetworkFailure();
    await viewModel.start();
    expect(viewModel.state, isA<VerifyEmailLoadFailed>());

    users.failure = null;
    await viewModel.start();

    expect(viewModel.state, isA<VerifyEmailReady>());
  });

  test('retrying from a load failure sends exactly one code', () async {
    users.failure = const NetworkFailure();
    await viewModel.start();
    expect(verification.sends, 0);

    users.failure = null;
    await viewModel.start();

    expect(verification.sends, 1);
  });

  test('retrying from a load failure after register sends no code', () async {
    pending.begin();
    final local = build();
    users.failure = const NetworkFailure();
    await local.start();

    users.failure = null;
    await local.start();

    expect(verification.sends, 0);
    expect(local.state, isA<VerifyEmailReady>());
    local.dispose();
  });

  test('an already verified account goes straight to verified, sending nothing', () async {
    users.emailVerified = true;

    await viewModel.start();

    expect(viewModel.state, isA<VerifyEmailVerified>());
    expect(verification.sends, 0);
  });

  test('confirm succeeds with the updated user', () async {
    await viewModel.start();

    await viewModel.confirm('042917');

    expect(verification.confirms, ['042917']);
    expect(
      viewModel.state,
      isA<VerifyEmailVerified>().having((s) => s.user.emailVerified, 'emailVerified', isTrue),
    );
  });

  test('invalid-code keeps the screen with the failure; editing clears it', () async {
    await viewModel.start();
    verification.confirmFailure = invalidCode;

    await viewModel.confirm('000000');
    expect(viewModel.state, isA<VerifyEmailReady>().having((s) => s.failure, 'failure', invalidCode));

    viewModel.clearFailure();
    expect(viewModel.state, isA<VerifyEmailReady>().having((s) => s.failure, 'failure', isNull));
  });

  test('a second confirm while one is in flight is ignored', () async {
    await viewModel.start();
    verification.gate = Completer<void>();

    final first = viewModel.confirm('042917');
    final second = viewModel.confirm('042917');
    verification.gate!.complete();
    await Future.wait([first, second]);

    expect(verification.confirms, hasLength(1));
  });

  test('skip ends the pending verification', () {
    pending.begin();

    viewModel.skip();

    expect(pending.isPending, isFalse);
  });

  test('the resend is refused during the cooldown and allowed after it', () {
    fakeAsync((async) {
      final local = build();
      unawaited(local.start());
      async.flushMicrotasks();
      expect(verification.sends, 1);

      unawaited(local.sendCode());
      async.flushMicrotasks();
      expect(verification.sends, 1);

      async.elapse(const Duration(seconds: 60));
      expect(local.cooldownSeconds, 0);
      unawaited(local.sendCode());
      async.flushMicrotasks();

      expect(verification.sends, 2);
      expect(local.cooldownSeconds, 60);
      local.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('never notifies or starts a timer after dispose', () {
    fakeAsync((async) {
      users.gate = Completer<void>();
      final local = build();
      var finished = false;
      unawaited(local.start().whenComplete(() => finished = true));
      local.dispose();

      users.gate!.complete();
      async.flushMicrotasks();

      expect(finished, isTrue);
      expect(async.pendingTimers, isEmpty);
    });
  });
}

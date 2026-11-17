import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/auth/password_reset/application/viewmodel/password_reset_view_model.dart';

import '../../../../../support/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository auth;
  late PasswordResetViewModel viewModel;

  const tooMany = ProblemFailure(status: 429, type: ProblemType.tooManyRequests);
  const invalidCode = ProblemFailure(status: 400, type: ProblemType.invalidCode);

  setUp(() {
    auth = FakeAuthRepository();
    viewModel = PasswordResetViewModel(auth: auth);
  });

  tearDown(() => viewModel.dispose());

  Future<void> reachCodeStep() => viewModel.requestCode(' ana@example.com ');

  test('starts on the email step', () {
    expect(viewModel.state, isA<PasswordResetEnterEmail>());
    expect(viewModel.cooldownSeconds, 0);
  });

  test('a 202 advances to the code step with the trimmed email and starts the cooldown', () async {
    final states = <PasswordResetState>[];
    viewModel.addListener(() => states.add(viewModel.state));

    await reachCodeStep();

    expect(states.first, isA<PasswordResetEnterEmail>().having((s) => s.busy, 'busy', isTrue));
    expect(viewModel.state, isA<PasswordResetEnterCode>().having((s) => s.email, 'email', 'ana@example.com'));
    expect(auth.resetRequests.single.email, 'ana@example.com');
    expect(viewModel.cooldownSeconds, 60);
  });

  test('a network failure stays on the email step with the failure', () async {
    auth.failure = const NetworkFailure();

    await reachCodeStep();

    expect(
      viewModel.state,
      isA<PasswordResetEnterEmail>()
          .having((s) => s.failure, 'failure', isA<NetworkFailure>())
          .having((s) => s.busy, 'busy', isFalse),
    );
    expect(viewModel.cooldownSeconds, 0);
  });

  test('a 429 on the request stays on the email step', () async {
    auth.failure = tooMany;

    await reachCodeStep();

    expect(viewModel.state, isA<PasswordResetEnterEmail>().having((s) => s.failure, 'f', tooMany));
  });

  test('a second request while one is in flight is ignored', () async {
    auth.gate = Completer<void>();

    final first = reachCodeStep();
    final second = reachCodeStep();
    auth.gate!.complete();
    await Future.wait([first, second]);

    expect(auth.resetRequests, hasLength(1));
  });

  test('confirm sends email, code and new password, then finishes', () async {
    await reachCodeStep();

    await viewModel.confirm(code: '042917', newPassword: 'fake-new-password');

    final sent = auth.resetConfirms.single;
    expect((sent.email, sent.code, sent.newPassword), ('ana@example.com', '042917', 'fake-new-password'));
    expect(viewModel.state, isA<PasswordResetDone>());
  });

  test('invalid-code keeps the code step with the failure', () async {
    await reachCodeStep();
    auth.failure = invalidCode;

    await viewModel.confirm(code: '000000', newPassword: 'fake-new-password');

    expect(
      viewModel.state,
      isA<PasswordResetEnterCode>()
          .having((s) => s.failure, 'failure', invalidCode)
          .having((s) => s.email, 'email', 'ana@example.com'),
    );
  });

  test('a 429 on confirm keeps the code step with the failure', () async {
    await reachCodeStep();
    auth.failure = tooMany;

    await viewModel.confirm(code: '042917', newPassword: 'fake-new-password');

    expect(viewModel.state, isA<PasswordResetEnterCode>().having((s) => s.failure, 'f', tooMany));
  });

  test('backToEmail cancels the cooldown and returns to the email step', () {
    fakeAsync((async) {
      final local = PasswordResetViewModel(auth: auth);
      unawaited(local.requestCode('ana@example.com'));
      async.flushMicrotasks();
      expect(local.cooldownSeconds, 60);

      local.backToEmail();

      expect(local.state, isA<PasswordResetEnterEmail>().having((s) => s.failure, 'failure', isNull));
      expect(local.cooldownSeconds, 0);
      expect(async.pendingTimers, isEmpty);
      local.dispose();
    });
  });

  test('backToEmail outside the code step is ignored', () {
    viewModel.backToEmail();

    expect(viewModel.state, isA<PasswordResetEnterEmail>());
  });

  test('confirm outside the code step is ignored', () async {
    await viewModel.confirm(code: '042917', newPassword: 'fake-new-password');

    expect(auth.resetConfirms, isEmpty);
    expect(viewModel.state, isA<PasswordResetEnterEmail>());
  });

  test('clearFailure drops the failure of either step', () async {
    auth.failure = tooMany;
    await reachCodeStep();
    viewModel.clearFailure();
    expect(viewModel.state, isA<PasswordResetEnterEmail>().having((s) => s.failure, 'f', isNull));

    auth.failure = null;
    await reachCodeStep();
    auth.failure = invalidCode;
    await viewModel.confirm(code: '000000', newPassword: 'fake-new-password');
    viewModel.clearFailure();
    expect(viewModel.state, isA<PasswordResetEnterCode>().having((s) => s.failure, 'f', isNull));
  });

  group('resend cooldown', () {
    test('counts down each second and re-enables the resend at zero', () {
      fakeAsync((async) {
        final local = PasswordResetViewModel(auth: auth);
        unawaited(local.requestCode('ana@example.com'));
        async.flushMicrotasks();
        expect(local.cooldownSeconds, 60);

        async.elapse(const Duration(seconds: 1));
        expect(local.cooldownSeconds, 59);

        // Resend is refused while counting.
        unawaited(local.resend());
        async.flushMicrotasks();
        expect(auth.resetRequests, hasLength(1));

        async.elapse(const Duration(seconds: 59));
        expect(local.cooldownSeconds, 0);

        unawaited(local.resend());
        async.flushMicrotasks();
        expect(auth.resetRequests, hasLength(2));
        expect(local.cooldownSeconds, 60);
        local.dispose();
      });
    });

    test('a refused resend shows the failure and waits again', () {
      fakeAsync((async) {
        final local = PasswordResetViewModel(auth: auth, cooldown: const Duration(seconds: 3));
        unawaited(local.requestCode('ana@example.com'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        auth.failure = tooMany;

        unawaited(local.resend());
        async.flushMicrotasks();

        expect(local.state, isA<PasswordResetEnterCode>().having((s) => s.failure, 'f', tooMany));
        expect(local.cooldownSeconds, 3);
        local.dispose();
      });
    });

    test('finishing the reset stops the timer', () {
      fakeAsync((async) {
        final local = PasswordResetViewModel(auth: auth);
        unawaited(local.requestCode('ana@example.com'));
        async.flushMicrotasks();
        unawaited(local.confirm(code: '042917', newPassword: 'fake-new-password'));
        async.flushMicrotasks();

        expect(local.state, isA<PasswordResetDone>());
        expect(async.pendingTimers, isEmpty);
        local.dispose();
      });
    });

    test('dispose cancels the timer', () {
      fakeAsync((async) {
        final local = PasswordResetViewModel(auth: auth);
        unawaited(local.requestCode('ana@example.com'));
        async.flushMicrotasks();
        expect(async.pendingTimers, isNotEmpty);

        local.dispose();

        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  test('never notifies or starts a timer after dispose, even when the answer arrives later', () {
    fakeAsync((async) {
      auth.gate = Completer<void>();
      final local = PasswordResetViewModel(auth: auth);
      var finished = false;
      unawaited(local.requestCode('ana@example.com').whenComplete(() => finished = true));
      local.dispose();

      auth.gate!.complete();
      async.flushMicrotasks();

      expect(finished, isTrue);
      expect(async.pendingTimers, isEmpty);
    });
  });
}

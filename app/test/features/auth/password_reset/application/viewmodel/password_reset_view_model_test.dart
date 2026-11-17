import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/auth/_shared/application/code_entry_status.dart';
import 'package:snapledger/features/auth/password_reset/application/viewmodel/password_reset_view_model.dart';

import '../../../../../support/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository auth;
  late PasswordResetViewModel viewModel;

  const tooMany = ProblemFailure(status: 429, type: ProblemType.tooManyRequests);
  const invalidCode = ProblemFailure(status: 400, type: ProblemType.invalidCode);
  const invalidToken = ProblemFailure(status: 400, type: ProblemType.invalidResetToken);

  setUp(() {
    auth = FakeAuthRepository();
    viewModel = PasswordResetViewModel(auth: auth, successPause: Duration.zero);
  });

  tearDown(() => viewModel.dispose());

  Future<void> reachCodeStep() => viewModel.requestCode(' ana@example.com ');

  Future<void> reachNewPasswordStep() async {
    await reachCodeStep();
    await viewModel.verifyCode('042917');
  }

  test('starts on the email step', () {
    expect(viewModel.state, isA<PasswordResetEnterEmail>());
    expect(viewModel.cooldownSeconds, 0);
  });

  test('a 202 advances to the code step with the trimmed email and starts the cooldown', () async {
    final states = <PasswordResetState>[];
    viewModel.addListener(() => states.add(viewModel.state));

    await reachCodeStep();

    expect(states.first, isA<PasswordResetEnterEmail>().having((s) => s.busy, 'busy', isTrue));
    expect(
      viewModel.state,
      isA<PasswordResetEnterCode>().having((s) => s.email, 'email', 'ana@example.com'),
    );
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

  group('verify code', () {
    test('success shows the success status, keeps the token and advances to the new password', () async {
      await reachCodeStep();
      final states = <PasswordResetState>[];
      viewModel.addListener(() => states.add(viewModel.state));

      await viewModel.verifyCode('042917');

      expect(
        states.map((s) => s is PasswordResetEnterCode ? s.status : null).toList(),
        [CodeEntryStatus.verifying, CodeEntryStatus.success, null],
      );
      expect(viewModel.state, isA<PasswordResetNewPassword>());
      final sent = auth.resetVerifies.single;
      expect((sent.email, sent.code), ('ana@example.com', '042917'));
      expect(viewModel.cooldownSeconds, 0);
    });

    test('the state never carries the reset token', () async {
      await reachNewPasswordStep();

      expect('${viewModel.state}', isNot(contains('fake-reset-token')));
    });

    test('waits the success pause before advancing', () {
      fakeAsync((async) {
        final local = PasswordResetViewModel(auth: auth);
        unawaited(local.requestCode('ana@example.com'));
        async.flushMicrotasks();
        unawaited(local.verifyCode('042917'));
        async.flushMicrotasks();

        expect(
          local.state,
          isA<PasswordResetEnterCode>().having((s) => s.status, 'status', CodeEntryStatus.success),
        );

        async.elapse(const Duration(milliseconds: 600));
        expect(local.state, isA<PasswordResetNewPassword>());
        local.dispose();
      });
    });

    test('invalid-code goes to the error status and allows retyping', () async {
      await reachCodeStep();
      auth.verifyFailure = invalidCode;

      await viewModel.verifyCode('000000');

      expect(
        viewModel.state,
        isA<PasswordResetEnterCode>()
            .having((s) => s.status, 'status', CodeEntryStatus.error)
            .having((s) => s.failure, 'failure', invalidCode),
      );

      viewModel.clearFailure();
      expect(
        viewModel.state,
        isA<PasswordResetEnterCode>()
            .having((s) => s.status, 'status', CodeEntryStatus.idle)
            .having((s) => s.failure, 'failure', isNull),
      );

      auth.verifyFailure = null;
      await viewModel.verifyCode('042917');
      expect(viewModel.state, isA<PasswordResetNewPassword>());
    });

    test('a 429 goes to the error status with the failure', () async {
      await reachCodeStep();
      auth.verifyFailure = tooMany;

      await viewModel.verifyCode('042917');

      expect(
        viewModel.state,
        isA<PasswordResetEnterCode>().having((s) => s.failure, 'failure', tooMany),
      );
    });

    test('verify outside the code step is ignored', () async {
      await viewModel.verifyCode('042917');

      expect(auth.resetVerifies, isEmpty);
    });

    test('a second verify while one is in flight is ignored', () async {
      await reachCodeStep();
      auth.gate = Completer<void>();

      final first = viewModel.verifyCode('042917');
      final second = viewModel.verifyCode('042917');
      auth.gate!.complete();
      await Future.wait([first, second]);

      expect(auth.resetVerifies, hasLength(1));
    });
  });

  group('new password', () {
    test('confirm sends the token and the new password, then finishes', () async {
      await reachNewPasswordStep();

      await viewModel.confirm('fake-new-password');

      final sent = auth.resetConfirms.single;
      expect((sent.resetToken, sent.newPassword), ('fake-reset-token', 'fake-new-password'));
      expect(viewModel.state, isA<PasswordResetDone>());
    });

    test('invalid-reset-token returns to the email step with the failure', () async {
      await reachNewPasswordStep();
      auth.confirmFailure = invalidToken;

      await viewModel.confirm('fake-new-password');

      expect(
        viewModel.state,
        isA<PasswordResetEnterEmail>().having((s) => s.failure, 'failure', invalidToken),
      );
      // The token is gone: a new confirm without a new verification does nothing.
      // PT: O token sumiu: um novo confirm sem nova verificação não faz nada.
      await viewModel.confirm('fake-new-password');
      expect(auth.resetConfirms, hasLength(1));
    });

    test('a 429 keeps the step with the failure', () async {
      await reachNewPasswordStep();
      auth.confirmFailure = tooMany;

      await viewModel.confirm('fake-new-password');

      expect(
        viewModel.state,
        isA<PasswordResetNewPassword>().having((s) => s.failure, 'failure', tooMany),
      );
    });

    test('confirm outside the new password step is ignored', () async {
      await viewModel.confirm('fake-new-password');

      expect(auth.resetConfirms, isEmpty);
      expect(viewModel.state, isA<PasswordResetEnterEmail>());
    });
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

  test('backToEmail from the new password step drops the token', () async {
    await reachNewPasswordStep();

    viewModel.backToEmail();
    await viewModel.confirm('fake-new-password');

    expect(viewModel.state, isA<PasswordResetEnterEmail>());
    expect(auth.resetConfirms, isEmpty);
  });

  test('backToEmail outside the code and new password steps is ignored', () {
    viewModel.backToEmail();

    expect(viewModel.state, isA<PasswordResetEnterEmail>());
  });

  test('clearFailure drops the failure of every step', () async {
    auth.failure = tooMany;
    await reachCodeStep();
    viewModel.clearFailure();
    expect(viewModel.state, isA<PasswordResetEnterEmail>().having((s) => s.failure, 'f', isNull));

    auth.failure = null;
    await reachCodeStep();
    auth.verifyFailure = tooMany;
    await viewModel.verifyCode('042917');
    viewModel.clearFailure();
    expect(viewModel.state, isA<PasswordResetEnterCode>().having((s) => s.failure, 'f', isNull));

    auth.verifyFailure = null;
    await viewModel.verifyCode('042917');
    auth.confirmFailure = tooMany;
    await viewModel.confirm('fake-new-password');
    viewModel.clearFailure();
    expect(viewModel.state, isA<PasswordResetNewPassword>().having((s) => s.failure, 'f', isNull));
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

    test('verifying the code stops the timer', () {
      fakeAsync((async) {
        final local = PasswordResetViewModel(auth: auth);
        unawaited(local.requestCode('ana@example.com'));
        async.flushMicrotasks();
        unawaited(local.verifyCode('042917'));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 600));

        expect(local.state, isA<PasswordResetNewPassword>());
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

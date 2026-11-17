import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/core/storage/secure_store.dart';
import 'package:snapledger/features/auth/register/application/viewmodel/register_view_model.dart';

import '../../../../../support/fake_auth_repository.dart';
import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/in_memory_secure_store.dart';

void main() {
  late FakeAuthRepository auth;
  late SessionNotifier session;
  late TokenStore tokens;
  late InMemorySecureStore store;
  late PendingVerification pending;
  late RegisterViewModel viewModel;
  late List<RegisterState> states;

  setUp(() {
    auth = FakeAuthRepository();
    (:session, :tokens, :store) = inMemorySession();
    pending = PendingVerification(session: session);
    viewModel = RegisterViewModel(auth: auth, session: session, pending: pending);
    states = [];
    viewModel.addListener(() => states.add(viewModel.state));
  });

  tearDown(() {
    pending.dispose();
    session.dispose();
  });

  Future<void> submit([RegisterViewModel? target]) => (target ?? viewModel).submit(
    name: 'Ana Souza',
    email: 'ana@example.com',
    password: 'fake-password',
  );

  test('a successful register marks the verification as pending before the sign-in', () async {
    var pendingWhenSignedIn = false;
    session.addListener(() => pendingWhenSignedIn = pending.isPending);

    await submit();

    expect(pendingWhenSignedIn, isTrue);
    expect(pending.isPending, isTrue);
  });

  test('a failed register leaves nothing pending', () async {
    auth.failure = const NetworkFailure();

    await submit();

    expect(pending.isPending, isFalse);
  });

  test('an unexpected error from the sign-in also leaves nothing pending', () async {
    store.beforeWrite = () async => throw StateError('boom');

    await expectLater(submit(), throwsStateError);

    expect(pending.isPending, isFalse);
    expect(session.status, isNot(SessionStatus.signedIn));
  });

  test('starts idle', () {
    expect(viewModel.state, isA<RegisterIdle>());
  });

  test('creates the account and signs in with the returned tokens', () async {
    await submit();

    expect(states, [isA<RegisterSubmitting>(), isA<RegisterSucceeded>()]);
    expect(session.status, SessionStatus.signedIn);
    expect(tokens.accessToken, 'fake-access-1');
    expect(store.values[TokenStore.refreshTokenKey], 'fake-refresh-1');
  });

  test('trims the ends of name and email but never touches the password', () async {
    await viewModel.submit(
      name: ' Ana Souza ',
      email: ' ana@example.com ',
      password: ' p4ss w0rd ',
    );

    final request = auth.registers.single;
    expect(request.name, 'Ana Souza');
    expect(request.email, 'ana@example.com');
    expect(request.password, ' p4ss w0rd ');
  });

  group('each failure becomes state and the session stays out', () {
    for (final failure in <Exception>[
      const ProblemFailure(status: 409, type: ProblemType.emailAlreadyRegistered),
      const ProblemFailure(status: 400, type: ProblemType.validationError, fieldErrors: ['name']),
      const ProblemFailure(status: 500, type: ProblemType.internalError),
      const NetworkFailure(),
    ]) {
      test('$failure', () async {
        auth.failure = failure;

        await submit();

        expect(states.first, isA<RegisterSubmitting>());
        expect(viewModel.state, isA<RegisterFailed>().having((s) => s.failure, 'failure', failure));
        expect(session.status, isNot(SessionStatus.signedIn));
      });
    }
  });

  test('a storage error while saving the tokens becomes state, not a crash', () async {
    store.failWrite = true;

    await submit();

    expect(
      viewModel.state,
      isA<RegisterFailed>().having((s) => s.failure, 'failure', isA<SecureStoreException>()),
    );
    expect(session.status, isNot(SessionStatus.signedIn));
    expect(pending.isPending, isFalse);
  });

  test('a second submit while the first is in flight is ignored', () async {
    auth.gate = Completer<void>();

    final first = submit();
    final second = submit();
    auth.gate!.complete();
    await Future.wait([first, second]);

    expect(auth.registers, hasLength(1));
  });

  test('a submit after success is ignored', () async {
    await submit();
    await submit();

    expect(auth.registers, hasLength(1));
  });

  test('can submit again after a failure', () async {
    auth.failure = const ProblemFailure(status: 409, type: ProblemType.emailAlreadyRegistered);
    await submit();
    auth.failure = null;

    await submit();

    expect(viewModel.state, isA<RegisterSucceeded>());
  });

  test('a storage error revokes the server session that could not be saved', () async {
    store.failWrite = true;

    await submit();

    expect(auth.logouts, ['fake-refresh-1']);
  });

  test('a failing revoke after a storage error is ignored', () async {
    store.failWrite = true;
    auth.logoutFailure = const NetworkFailure();

    await submit();

    expect(viewModel.state, isA<RegisterFailed>());
  });

  test('an API failure revokes nothing', () async {
    auth.failure = const NetworkFailure();

    await submit();

    expect(auth.logouts, isEmpty);
  });

  group('clearFailure', () {
    test('goes from failed to idle and notifies once', () async {
      auth.failure = const NetworkFailure();
      await submit();
      states.clear();

      viewModel.clearFailure();

      expect(states, [isA<RegisterIdle>()]);
    });

    test('does nothing while idle', () {
      viewModel.clearFailure();

      expect(states, isEmpty);
      expect(viewModel.state, isA<RegisterIdle>());
    });

    test('is ignored while submitting', () async {
      auth.gate = Completer<void>();
      final submitting = submit();
      states.clear();

      viewModel.clearFailure();

      expect(states, isEmpty);
      expect(viewModel.state, isA<RegisterSubmitting>());
      auth.gate!.complete();
      await submitting;
    });
  });

  test('never notifies after dispose, even when the answer arrives later', () async {
    auth.gate = Completer<void>();
    final local = RegisterViewModel(auth: auth, session: session, pending: pending);
    final submitting = submit(local);
    local.dispose();

    auth.gate!.complete();

    await expectLater(submitting, completes);
  });
}

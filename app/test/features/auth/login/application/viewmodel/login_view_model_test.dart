import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/core/storage/secure_store.dart';
import 'package:snapledger/features/auth/login/application/viewmodel/login_view_model.dart';

import '../../../../../support/fake_auth_repository.dart';
import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/in_memory_secure_store.dart';

void main() {
  late FakeAuthRepository auth;
  late SessionNotifier session;
  late TokenStore tokens;
  late InMemorySecureStore store;
  late PendingVerification pending;
  late LoginViewModel viewModel;
  late List<LoginState> states;

  setUp(() {
    auth = FakeAuthRepository();
    (:session, :tokens, :store) = inMemorySession();
    pending = PendingVerification(session: session);
    viewModel = LoginViewModel(auth: auth, session: session, pending: pending);
    states = [];
    viewModel.addListener(() => states.add(viewModel.state));
  });

  tearDown(() {
    pending.dispose();
    session.dispose();
  });

  test('a stale pending flag is cleared before the sign-in, so the login is a normal one', () async {
    pending.begin();
    var pendingWhenSignedIn = true;
    session.addListener(() => pendingWhenSignedIn = pending.isPending);

    await viewModel.submit(email: 'ana@example.com', password: 'fake-password');

    expect(pendingWhenSignedIn, isFalse);
    expect(pending.isPending, isFalse);
  });

  test('starts idle', () {
    expect(viewModel.state, isA<LoginIdle>());
  });

  test('signs in with the returned tokens, which are persisted first', () async {
    await viewModel.submit(email: 'ana@example.com', password: 'fake-password');

    expect(states, [isA<LoginSubmitting>(), isA<LoginSucceeded>()]);
    expect(session.status, SessionStatus.signedIn);
    expect(tokens.accessToken, 'fake-access-1');
    expect(store.values[TokenStore.refreshTokenKey], 'fake-refresh-1');
  });

  test('trims the ends of the email but never touches the password', () async {
    await viewModel.submit(email: '  ana@example.com ', password: ' fake password ');

    expect(auth.logins.single.email, 'ana@example.com');
    expect(auth.logins.single.password, ' fake password ');
  });

  group('each failure becomes state and the session stays out', () {
    for (final failure in <Exception>[
      const ProblemFailure(status: 401, type: ProblemType.invalidCredentials),
      const ProblemFailure(status: 400, type: ProblemType.validationError, fieldErrors: ['email']),
      const ProblemFailure(status: 500, type: ProblemType.internalError, errorId: 'abc'),
      const NetworkFailure(),
    ]) {
      test('$failure', () async {
        auth.failure = failure;

        await viewModel.submit(email: 'ana@example.com', password: 'fake-password');

        expect(states.first, isA<LoginSubmitting>());
        expect(viewModel.state, isA<LoginFailed>().having((s) => s.failure, 'failure', failure));
        expect(session.status, isNot(SessionStatus.signedIn));
      });
    }
  });

  test('a storage error while saving the tokens becomes state, not a crash', () async {
    store.failWrite = true;

    await viewModel.submit(email: 'ana@example.com', password: 'fake-password');

    expect(
      viewModel.state,
      isA<LoginFailed>().having((s) => s.failure, 'failure', isA<SecureStoreException>()),
    );
    expect(session.status, isNot(SessionStatus.signedIn));
    expect(tokens.accessToken, isNull);
  });

  test('can submit again after a failure', () async {
    auth.failure = const NetworkFailure();
    await viewModel.submit(email: 'ana@example.com', password: 'fake-password');
    auth.failure = null;

    await viewModel.submit(email: 'ana@example.com', password: 'fake-password');

    expect(viewModel.state, isA<LoginSucceeded>());
    expect(auth.logins, hasLength(2));
  });

  test('a second submit while the first is in flight is ignored', () async {
    auth.gate = Completer<void>();

    final first = viewModel.submit(email: 'ana@example.com', password: 'fake-password');
    final second = viewModel.submit(email: 'ana@example.com', password: 'fake-password');
    auth.gate!.complete();
    await Future.wait([first, second]);

    expect(auth.logins, hasLength(1));
    expect(viewModel.state, isA<LoginSucceeded>());
  });

  test('a submit after success is ignored', () async {
    await viewModel.submit(email: 'ana@example.com', password: 'fake-password');

    await viewModel.submit(email: 'ana@example.com', password: 'fake-password');

    expect(auth.logins, hasLength(1));
  });

  test('a storage error revokes the server session that could not be saved', () async {
    store.failWrite = true;

    await viewModel.submit(email: 'ana@example.com', password: 'fake-password');

    expect(auth.logouts, ['fake-refresh-1']);
  });

  test('a failing revoke after a storage error is ignored', () async {
    store.failWrite = true;
    auth.logoutFailure = const NetworkFailure();

    await viewModel.submit(email: 'ana@example.com', password: 'fake-password');

    expect(viewModel.state, isA<LoginFailed>());
  });

  test('an API failure revokes nothing', () async {
    auth.failure = const NetworkFailure();

    await viewModel.submit(email: 'ana@example.com', password: 'fake-password');

    expect(auth.logouts, isEmpty);
  });

  group('clearFailure', () {
    test('goes from failed to idle and notifies once', () async {
      auth.failure = const NetworkFailure();
      await viewModel.submit(email: 'ana@example.com', password: 'fake-password');
      states.clear();

      viewModel.clearFailure();

      expect(states, [isA<LoginIdle>()]);
    });

    test('does nothing while idle', () {
      viewModel.clearFailure();

      expect(states, isEmpty);
      expect(viewModel.state, isA<LoginIdle>());
    });

    test('is ignored while submitting', () async {
      auth.gate = Completer<void>();
      final submitting = viewModel.submit(email: 'ana@example.com', password: 'fake-password');
      states.clear();

      viewModel.clearFailure();

      expect(states, isEmpty);
      expect(viewModel.state, isA<LoginSubmitting>());
      auth.gate!.complete();
      await submitting;
    });
  });

  test('never notifies after dispose, even when the answer arrives later', () async {
    auth.gate = Completer<void>();
    final local = LoginViewModel(auth: auth, session: session, pending: pending);
    final submitting = local.submit(email: 'ana@example.com', password: 'fake-password');
    local.dispose();

    auth.gate!.complete();

    // A notify after dispose would throw a FlutterError here.
    // PT: Um notify depois do dispose lançaria um FlutterError aqui.
    await expectLater(submitting, completes);
  });
}

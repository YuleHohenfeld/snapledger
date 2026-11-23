import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/features/profile/overview/application/viewmodel/profile_view_model.dart';

import '../../../../../support/fake_auth_repository.dart';
import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/fake_user_repository.dart';
import '../../../../../support/in_memory_secure_store.dart';

/// A session whose sign out throws, to prove the view model resets its flag.
/// PT: Uma sessão cujo logout lança, para provar que o view model reinicia a flag.
class _ThrowingSession extends SessionNotifier {
  _ThrowingSession()
    : super(
        tokens: TokenStore(InMemorySecureStore()),
        refresher: FakeSessionRefresher(() async => const TemporaryFailure()),
      );

  @override
  Future<void> signOut({required Future<void> Function(String refreshToken) revoke}) =>
      Future.error(StateError('wipe failed'));
}

void main() {
  late FakeUserRepository users;
  late FakeAuthRepository auth;
  late SessionNotifier session;
  late TokenStore tokens;
  late ProfileViewModel viewModel;
  late List<ProfileState> states;

  setUp(() async {
    users = FakeUserRepository();
    auth = FakeAuthRepository();
    final stack = inMemorySession();
    session = stack.session;
    tokens = stack.tokens;
    await session.signIn(auth.response.tokens);
    viewModel = ProfileViewModel(users: users, auth: auth, session: session);
    states = [];
    viewModel.addListener(() => states.add(viewModel.state));
  });

  tearDown(() => session.dispose());

  test('starts loading', () {
    expect(viewModel.state, isA<ProfileLoading>());
  });

  test('load shows the user', () async {
    await viewModel.load();

    expect(
      viewModel.state,
      isA<ProfileLoaded>().having((s) => s.user.email, 'email', 'ana@example.com'),
    );
    expect(states, hasLength(1));
  });

  test('load after dispose does nothing and never notifies', () async {
    viewModel.dispose();

    await viewModel.load();

    expect(users.calls, 0);
  });

  test('a failure becomes state, and retry loads again', () async {
    users.failure = const NetworkFailure();
    await viewModel.load();
    expect(viewModel.state, isA<ProfileFailed>());

    users.failure = null;
    await viewModel.load();

    expect(states, [isA<ProfileFailed>(), isA<ProfileLoading>(), isA<ProfileLoaded>()]);
  });

  test('logout revokes the refresh token and wipes the session', () async {
    await viewModel.logout();

    expect(auth.logouts, ['fake-refresh-1']);
    expect(session.status, SessionStatus.signedOut);
    expect(tokens.accessToken, isNull);
  });

  test('logout wipes even when the API fails', () async {
    auth.logoutFailure = const NetworkFailure();

    await viewModel.logout();

    expect(session.status, SessionStatus.signedOut);
    expect(tokens.accessToken, isNull);
  });

  test('a second logout while the first runs is ignored', () async {
    final first = viewModel.logout();
    final second = viewModel.logout();
    expect(viewModel.loggingOut, isTrue);
    await Future.wait([first, second]);

    expect(auth.logouts, hasLength(1));
  });

  test('loggingOut is reset when the sign out throws', () async {
    final throwing = _ThrowingSession();
    addTearDown(throwing.dispose);
    final local = ProfileViewModel(users: users, auth: auth, session: throwing);

    await expectLater(local.logout(), throwsStateError);

    expect(local.loggingOut, isFalse);
  });

  test('never notifies after dispose, even when the answer arrives later', () async {
    users.gate = Completer<void>();
    final local = ProfileViewModel(users: users, auth: auth, session: session);
    final loading = local.load();
    local.dispose();

    users.gate!.complete();

    await expectLater(loading, completes);
  });
}

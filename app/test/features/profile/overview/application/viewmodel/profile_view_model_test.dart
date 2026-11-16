import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/features/profile/overview/application/viewmodel/profile_view_model.dart';

import '../../../../../support/fake_auth_repository.dart';
import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/fake_user_repository.dart';

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
    await Future.wait([first, second]);

    expect(auth.logouts, hasLength(1));
    expect(viewModel.loggingOut, isTrue);
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

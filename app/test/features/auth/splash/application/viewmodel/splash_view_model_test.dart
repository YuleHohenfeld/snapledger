import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/features/auth/splash/application/viewmodel/splash_view_model.dart';

import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/in_memory_secure_store.dart';

void main() {
  late FakeSessionRefresher refresher;
  late SessionNotifier session;
  late SplashViewModel viewModel;
  late List<SplashState> states;

  setUp(() {
    refresher = FakeSessionRefresher(() async => const TemporaryFailure());
    session = SessionNotifier(tokens: TokenStore(InMemorySecureStore()), refresher: refresher);
    viewModel = SplashViewModel(session: session);
    states = [];
    viewModel.addListener(() => states.add(viewModel.state));
  });

  tearDown(() {
    viewModel.dispose();
    session.dispose();
  });

  test('starts restoring and does not notify on start', () async {
    expect(viewModel.state, isA<SplashRestoring>());

    refresher.onRefresh = () async => const SessionEnded();
    await viewModel.start();

    expect(states, isEmpty);
    expect(session.status, SessionStatus.signedOut);
  });

  test('a verdict leaves the state to the router', () async {
    refresher.onRefresh = () async => const Refreshed('fake-access-1');

    await viewModel.start();

    expect(session.status, SessionStatus.signedIn);
    expect(viewModel.state, isA<SplashRestoring>());
  });

  test('no verdict turns into failed', () async {
    await viewModel.start();

    expect(viewModel.state, isA<SplashRestoreFailed>());
    expect(session.status, SessionStatus.unknown);
  });

  test('retry goes back to restoring and checks again', () async {
    await viewModel.start();
    refresher.onRefresh = () async => const Refreshed('fake-access-1');

    await viewModel.retry();

    expect(refresher.calls, 2);
    expect(states, [isA<SplashRestoreFailed>(), isA<SplashRestoring>()]);
    expect(session.status, SessionStatus.signedIn);
  });

  test('sign in again wipes the session', () async {
    await viewModel.start();

    await viewModel.signInAgain();

    expect(session.status, SessionStatus.signedOut);
  });
}

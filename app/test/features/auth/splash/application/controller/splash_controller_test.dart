import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/features/auth/splash/application/controller/splash_controller.dart';
import 'package:snapledger/features/auth/splash/application/viewmodel/splash_view_model.dart';

import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/in_memory_secure_store.dart';

void main() {
  late FakeSessionRefresher refresher;
  late SessionNotifier session;
  late SplashViewModel viewModel;
  late SplashController controller;

  setUp(() {
    refresher = FakeSessionRefresher(() async => const TemporaryFailure());
    session = SessionNotifier(tokens: TokenStore(InMemorySecureStore()), refresher: refresher);
    viewModel = SplashViewModel(session: session);
    controller = SplashController(viewModel: viewModel);
  });

  tearDown(() {
    viewModel.dispose();
    session.dispose();
  });

  test('start checks the session once', () async {
    controller.start();
    await pumpEventQueue();

    expect(refresher.calls, 1);
    expect(viewModel.state, isA<SplashRestoreFailed>());
  });

  test('the retry tap checks again', () async {
    controller.start();
    await pumpEventQueue();

    controller.onRetryTapped();
    await pumpEventQueue();

    expect(refresher.calls, 2);
  });

  test('the sign-in-again tap wipes the session', () async {
    controller.start();
    await pumpEventQueue();

    controller.onSignInAgainTapped();
    await pumpEventQueue();

    expect(session.status, SessionStatus.signedOut);
  });
}

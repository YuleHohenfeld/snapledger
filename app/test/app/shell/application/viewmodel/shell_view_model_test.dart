import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/app/shell/application/viewmodel/shell_view_model.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';

import '../../../../support/fake_auth_repository.dart';
import '../../../../support/fake_session_refresher.dart';
import '../../../../support/in_memory_secure_store.dart';

/// A session whose sign out waits for [gate] and then throws when [fail] is set.
/// PT: Uma sessão cujo logout espera o [gate] e depois lança quando [fail] está ligado.
class _GatedSession extends SessionNotifier {
  _GatedSession()
    : super(
        tokens: TokenStore(InMemorySecureStore()),
        refresher: FakeSessionRefresher(() async => const TemporaryFailure()),
      );

  final gate = Completer<void>();
  bool fail = false;
  int signOuts = 0;

  @override
  Future<void> signOut({required Future<void> Function(String refreshToken) revoke}) async {
    signOuts++;
    await gate.future;
    if (fail) throw StateError('wipe failed');
  }
}

void main() {
  late _GatedSession session;
  late ShellViewModel viewModel;
  late int notifications;

  setUp(() {
    session = _GatedSession();
    viewModel = ShellViewModel(auth: FakeAuthRepository(), session: session);
    notifications = 0;
    viewModel.addListener(() => notifications++);
  });

  tearDown(() {
    viewModel.dispose();
    session.dispose();
  });

  test('starts idle', () {
    expect(viewModel.loggingOut, isFalse);
  });

  test('logout sets loggingOut and notifies, and stays set on success', () async {
    final running = viewModel.logout();

    expect(viewModel.loggingOut, isTrue);
    expect(notifications, 1);

    session.gate.complete();
    await running;

    // The router leaves the screen after a sign out, so the flag is not cleared.
    // PT: O router sai da tela após o logout, então a flag não é limpa.
    expect(viewModel.loggingOut, isTrue);
    expect(notifications, 1);
  });

  test('a logout while one is running is ignored', () async {
    final first = viewModel.logout();
    final second = viewModel.logout();
    session.gate.complete();
    await Future.wait([first, second]);

    expect(session.signOuts, 1);
  });

  test('loggingOut is reset after the sign out throws', () async {
    session.fail = true;
    final running = viewModel.logout();
    session.gate.complete();

    await expectLater(running, throwsStateError);

    expect(viewModel.loggingOut, isFalse);
    expect(notifications, 2);
  });

  test('never notifies after dispose, even when the sign out then fails', () async {
    final local = ShellViewModel(auth: FakeAuthRepository(), session: session);
    var localNotifications = 0;
    local.addListener(() => localNotifications++);
    session.fail = true;
    final running = local.logout();
    local.dispose();

    session.gate.complete();
    await expectLater(running, throwsStateError);

    expect(localNotifications, 1);
  });
}

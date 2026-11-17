import 'package:flutter/foundation.dart';
import 'package:snapledger/core/session/session_notifier.dart';

/// What the splash screen shows while the stored session is checked.
/// PT: O que o splash mostra enquanto a sessão guardada é verificada.
/// Notes: docs/code-notes/app-auth.md#splashviewmodel
@immutable
sealed class SplashState {
  const SplashState();
}

final class SplashRestoring extends SplashState {
  const SplashRestoring();
}

/// The check could not reach a verdict (offline, server error); the session may still be valid.
/// PT: A verificação não chegou a um veredito (offline, erro do servidor); a sessão ainda pode ser válida.
final class SplashRestoreFailed extends SplashState {
  const SplashRestoreFailed();
}

/// Business state of the splash: runs the cold-start session check and offers retry or a clean start.
/// PT: Estado de negócio do splash: roda a verificação da sessão no cold start e oferece repetir ou recomeçar.
/// Notes: docs/code-notes/app-auth.md#splashviewmodel
class SplashViewModel extends ChangeNotifier {
  SplashViewModel({required this._session});

  final SessionNotifier _session;
  SplashState _state = const SplashRestoring();
  bool _disposed = false;

  SplashState get state => _state;

  /// Checks the session; on a verdict the router leaves the splash, otherwise the state turns failed.
  /// PT: Verifica a sessão; com veredito o router sai do splash, senão o estado vira failed.
  Future<void> start() async {
    await _session.restore();
    if (_session.status == SessionStatus.unknown) _emit(const SplashRestoreFailed());
  }

  /// Back to the spinner and checks again.
  /// PT: Volta ao spinner e verifica de novo.
  Future<void> retry() async {
    _emit(const SplashRestoring());
    await start();
  }

  /// Gives up on the stored session: wipes it, and the router goes to login.
  /// PT: Desiste da sessão guardada: apaga-a, e o router vai para o login.
  Future<void> signInAgain() => _session.wipe();

  // Also skips a no-op emit, so calling start() from initState never notifies during build.
  // PT: Também pula um emit sem mudança, então chamar start() no initState nunca notifica durante o build.
  void _emit(SplashState next) {
    if (_disposed || _state.runtimeType == next.runtimeType) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

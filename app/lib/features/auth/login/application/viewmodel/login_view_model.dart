import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/storage/secure_store.dart';
import 'package:snapledger/features/auth/_shared/data/models/auth_response.dart';
import 'package:snapledger/features/auth/_shared/data/models/login_request.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';

/// Where the login stands; the View draws it and never sees a message string.
/// PT: Em que pé está o login; a View o desenha e nunca recebe uma string de mensagem.
/// Notes: docs/code-notes/app-auth.md#loginviewmodel
@immutable
sealed class LoginState {
  const LoginState();
}

final class LoginIdle extends LoginState {
  const LoginIdle();
}

final class LoginSubmitting extends LoginState {
  const LoginSubmitting();
}

/// Signed in; the router leaves the screen, and further submits are ignored meanwhile.
/// PT: Logado; o router sai da tela, e novos envios são ignorados enquanto isso.
final class LoginSucceeded extends LoginState {
  const LoginSucceeded();
}

final class LoginFailed extends LoginState {
  const LoginFailed(this.failure);

  /// An [ApiFailure] or a [SecureStoreException]; the View localizes it.
  /// PT: Um [ApiFailure] ou um [SecureStoreException]; a View o traduz.
  final Exception failure;
}

/// Business state of the login screen: calls the API, then hands the tokens to the session.
/// PT: Estado de negócio da tela de login: chama a API e entrega os tokens à sessão.
/// Notes: docs/code-notes/app-auth.md#loginviewmodel
class LoginViewModel extends ChangeNotifier {
  LoginViewModel({
    required this._auth,
    required this._session,
    required this._pending,
  });

  final AuthRepository _auth;
  final SessionNotifier _session;
  final PendingVerification _pending;
  LoginState _state = const LoginIdle();
  bool _disposed = false;

  LoginState get state => _state;

  /// Ignored while a submit is in flight or after success; the email's ends are trimmed, the password never.
  /// PT: Ignorado com um envio em andamento ou após o sucesso; o email tem as pontas aparadas, a senha nunca.
  Future<void> submit({required String email, required String password}) async {
    if (_state is LoginSubmitting || _state is LoginSucceeded) return;
    _emit(const LoginSubmitting());
    AuthResponse? response;
    try {
      response = await _auth.login(LoginRequest(email: email.trim(), password: password));
      // A stale flag must never pin a normal login to the Verify email screen.
      // PT: Uma flag velha nunca pode prender um login normal na tela de verificar email.
      // Notes: docs/code-notes/app-auth.md#pending-verification
      _pending.clear();
      await _session.signIn(response.tokens);
      _emit(const LoginSucceeded());
    } on ApiFailure catch (failure) {
      _emit(LoginFailed(failure));
    } on SecureStoreException catch (failure) {
      _emit(LoginFailed(failure));
      // The server already opened a session the device could not save: close it.
      // PT: O servidor já abriu uma sessão que o aparelho não conseguiu salvar: fecha-se.
      // Notes: docs/code-notes/app-auth.md#orphan-session
      if (response != null) await _revokeOrphan(response.tokens.refreshToken);
    }
  }

  Future<void> _revokeOrphan(String refreshToken) async {
    try {
      await _auth.logout(refreshToken).timeout(SessionNotifier.revokeTimeout);
    } on Exception {
      // Best effort: the session simply expires on the server.
      // PT: Melhor esforço: a sessão simplesmente expira no servidor.
    }
  }

  /// Back to idle after a failure, so a stale error disappears once the user edits a field.
  /// PT: Volta a idle após uma falha, para o erro antigo sumir quando o usuário edita um campo.
  /// Notes: docs/code-notes/app-auth.md#onsubmit
  void clearFailure() {
    if (_state is LoginFailed) _emit(const LoginIdle());
  }

  // An answer that arrives after the screen closed must not notify a disposed notifier.
  // PT: Uma resposta que chega depois que a tela fechou não pode notificar um notifier descartado.
  void _emit(LoginState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

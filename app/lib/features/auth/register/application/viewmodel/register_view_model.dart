import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/storage/secure_store.dart';
import 'package:snapledger/features/auth/_shared/data/models/auth_response.dart';
import 'package:snapledger/features/auth/_shared/data/models/register_request.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';

/// Where the registration stands; the View draws it and never sees a message string.
/// PT: Em que pé está o cadastro; a View o desenha e nunca recebe uma string de mensagem.
/// Notes: docs/code-notes/app-auth.md#registerviewmodel
@immutable
sealed class RegisterState {
  const RegisterState();
}

final class RegisterIdle extends RegisterState {
  const RegisterIdle();
}

final class RegisterSubmitting extends RegisterState {
  const RegisterSubmitting();
}

/// Account created and signed in; the router leaves the screen, and further submits are ignored.
/// PT: Conta criada e logada; o router sai da tela, e novos envios são ignorados.
final class RegisterSucceeded extends RegisterState {
  const RegisterSucceeded();
}

final class RegisterFailed extends RegisterState {
  const RegisterFailed(this.failure);

  /// An [ApiFailure] or a [SecureStoreException]; the View localizes it.
  /// PT: Um [ApiFailure] ou um [SecureStoreException]; a View o traduz.
  final Exception failure;
}

/// Business state of the register screen: creates the account, then hands the tokens to the session.
/// PT: Estado de negócio da tela de cadastro: cria a conta e entrega os tokens à sessão.
/// Notes: docs/code-notes/app-auth.md#registerviewmodel
class RegisterViewModel extends ChangeNotifier {
  RegisterViewModel({required this._auth, required this._session});

  final AuthRepository _auth;
  final SessionNotifier _session;
  RegisterState _state = const RegisterIdle();
  bool _disposed = false;

  RegisterState get state => _state;

  /// Ignored while a submit is in flight or after success; name and email are trimmed, the password never.
  /// PT: Ignorado com um envio em andamento ou após o sucesso; nome e email são aparados, a senha nunca.
  Future<void> submit({
    required String name,
    required String email,
    required String password,
  }) async {
    if (_state is RegisterSubmitting || _state is RegisterSucceeded) return;
    _emit(const RegisterSubmitting());
    AuthResponse? response;
    try {
      response = await _auth.register(
        RegisterRequest(name: name.trim(), email: email.trim(), password: password),
      );
      await _session.signIn(response.tokens);
      _emit(const RegisterSucceeded());
    } on ApiFailure catch (failure) {
      _emit(RegisterFailed(failure));
    } on SecureStoreException catch (failure) {
      _emit(RegisterFailed(failure));
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
    if (_state is RegisterFailed) _emit(const RegisterIdle());
  }

  // An answer that arrives after the screen closed must not notify a disposed notifier.
  // PT: Uma resposta que chega depois que a tela fechou não pode notificar um notifier descartado.
  void _emit(RegisterState next) {
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

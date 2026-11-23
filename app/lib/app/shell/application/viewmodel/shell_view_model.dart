import 'package:flutter/foundation.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';

/// Business state of the signed-in frame: only the sign out of its account menu.
/// PT: Estado de negócio da moldura logada: só o logout do menu da conta.
/// Notes: docs/code-notes/app-core.md#responsive-shell
class ShellViewModel extends ChangeNotifier {
  ShellViewModel({required this._auth, required this._session});

  final AuthRepository _auth;
  final SessionNotifier _session;
  bool _loggingOut = false;
  bool _disposed = false;

  /// True from the tap on sign out until the router leaves the screen.
  /// PT: Verdadeiro do toque em sair até o router sair da tela.
  bool get loggingOut => _loggingOut;

  /// Same path as the profile's sign out: revoke best effort, then wipe locally; ignored if running.
  /// PT: Mesmo caminho do sair do perfil: revoga com melhor esforço e limpa localmente; ignorado se rodando.
  Future<void> logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    if (!_disposed) notifyListeners();
    var done = false;
    try {
      await _session.signOut(revoke: _auth.logout);
      done = true;
    } finally {
      // A throwing wipe must not leave the menu item disabled forever; on success it stays disabled
      // until the router leaves the screen.
      // PT: Um wipe que lança não pode deixar o item do menu desativado para sempre; no sucesso ele
      // fica desativado até o router sair da tela.
      if (!done) {
        _loggingOut = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

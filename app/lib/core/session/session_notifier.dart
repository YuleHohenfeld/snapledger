import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/token_response.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/core/storage/secure_store.dart';

/// Where the session stands; the router decides which screens are allowed from it.
/// PT: Em que pé está a sessão; o router decide a partir dela quais telas são permitidas.
enum SessionStatus { unknown, signedOut, signedIn }

/// App-wide session state; the only class that moves it between signed in and signed out.
/// PT: Estado de sessão do app inteiro; a única classe que o move entre logado e deslogado.
/// Notes: docs/code-notes/app-core.md#sessionnotifier
class SessionNotifier extends ChangeNotifier {
  SessionNotifier({required this._tokens, required this._refresher});

  /// Best-effort revoke limit on sign-out (ADR 0011). PT: Limite do revoke best effort ao sair (ADR 0011).
  static const revokeTimeout = Duration(seconds: 5);

  final TokenStore _tokens;
  final SessionRefresher _refresher;
  SessionStatus _status = SessionStatus.unknown;
  bool _restoreFailed = false;
  Future<void>? _restoring;
  Future<void>? _signingOut;
  bool _disposed = false;

  SessionStatus get status => _status;

  /// True while [status] is unknown because the last [restore] could not reach a verdict.
  /// PT: Verdadeiro enquanto [status] é unknown porque o último [restore] não chegou a um veredito.
  bool get restoreFailed => _restoreFailed;

  /// Cold start: one refresh decides the state; calls while one runs share it.
  /// PT: Cold start: um refresh decide o estado; chamadas durante a execução o compartilham.
  /// Notes: docs/code-notes/app-core.md#restore
  Future<void> restore() => _restoring ??= _restore().whenComplete(() => _restoring = null);

  Future<void> _restore() async {
    if (_status != SessionStatus.unknown) return;
    _update(SessionStatus.unknown, restoreFailed: false);
    final outcome = await _refresher.refresh();
    // A sign-in or wipe during the refresh already decided the state: the old outcome must not undo it.
    // PT: Um login ou wipe durante o refresh já decidiu o estado: o resultado antigo não pode desfazê-lo.
    if (_status != SessionStatus.unknown) return;
    switch (outcome) {
      case Refreshed():
        _update(SessionStatus.signedIn);
      case SessionEnded():
        _update(SessionStatus.signedOut);
      case TemporaryFailure():
        _update(SessionStatus.unknown, restoreFailed: true);
    }
  }

  /// Saves the new pair first, then signs in; throws [SecureStoreException] if it could not save.
  /// PT: Salva o novo par antes, depois entra; lança [SecureStoreException] se não conseguiu salvar.
  Future<void> signIn(TokenResponse tokens) async {
    await _tokens.save(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
    _update(SessionStatus.signedIn);
  }

  /// Forgets the tokens and signs out; never throws, even if the device storage fails.
  /// PT: Esquece os tokens e sai; nunca lança, mesmo se o armazenamento do aparelho falhar.
  /// Notes: docs/code-notes/app-core.md#wipe
  Future<void> wipe() async {
    try {
      await _tokens.clear();
    } on SecureStoreException {
      // Memory is clear, the epoch moved and the delete is pending: the next read retries it.
      // PT: A memória está limpa, o epoch mudou e o delete ficou pendente: a próxima leitura o refaz.
    }
    _update(SessionStatus.signedOut);
  }

  /// Revokes on the server (best effort, short timeout), then wipes locally regardless.
  /// PT: Revoga no servidor (melhor esforço, timeout curto), depois limpa localmente de qualquer jeito.
  /// Single-flight: a call while one runs gets the same future, so the revoke is sent once.
  /// PT: Voo único: uma chamada durante a execução recebe o mesmo future, então o revoke sai uma vez.
  /// Notes: docs/code-notes/app-core.md#signout
  Future<void> signOut({required Future<void> Function(String refreshToken) revoke}) =>
      _signingOut ??= _signOut(revoke).whenComplete(() => _signingOut = null);

  Future<void> _signOut(Future<void> Function(String refreshToken) revoke) async {
    try {
      final refreshToken = await _tokens.readRefreshToken();
      if (refreshToken != null) await revoke(refreshToken).timeout(revokeTimeout);
    } on Exception {
      // Offline, timeout or server error: the local wipe below still signs the user out.
      // PT: Offline, timeout ou erro do servidor: o wipe local abaixo ainda desloga o usuário.
    } finally {
      await wipe();
    }
  }

  void _update(SessionStatus status, {bool restoreFailed = false}) {
    if (_disposed || (status == _status && restoreFailed == _restoreFailed)) return;
    _status = status;
    _restoreFailed = restoreFailed;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

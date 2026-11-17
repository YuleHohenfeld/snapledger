import 'package:flutter/foundation.dart';
import 'package:snapledger/core/session/session_notifier.dart';

/// One-shot flag "show the Verify email screen next", set by a successful register; the router reads it.
/// PT: Flag de uso único "mostre a tela de verificar email em seguida", ligada por um cadastro bem-sucedido; o router a lê.
/// Notes: docs/code-notes/app-auth.md#pending-verification
class PendingVerification extends ChangeNotifier {
  /// Clears itself when the session ends, so a later login never lands on the verification.
  /// PT: Limpa-se quando a sessão termina, para um login futuro nunca cair na verificação.
  PendingVerification({required this._session}) {
    _session.addListener(_onSessionChanged);
  }

  final SessionNotifier _session;
  bool _pending = false;
  bool _disposed = false;

  bool get isPending => _pending;

  /// Call before signing in, so the redirect that follows already sees the flag.
  /// PT: Chame antes de entrar na sessão, para o redirect seguinte já enxergar a flag.
  void begin() => _set(true);

  void clear() => _set(false);

  void _onSessionChanged() {
    if (_session.status == SessionStatus.signedOut) clear();
  }

  void _set(bool value) {
    if (_disposed || _pending == value) return;
    _pending = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }
}

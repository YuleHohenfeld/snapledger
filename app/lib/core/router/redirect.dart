import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/session/session_notifier.dart';

/// The only places a `?from=` may send the user back to; everything else is refused.
/// PT: Os únicos lugares para onde um `?from=` pode devolver o usuário; todo o resto é recusado.
/// Notes: docs/code-notes/app-core.md#redirectfor
const _fromAllowlist = {'/summary', '/expenses', '/profile'};

const _tabRoots = [AppRoute.summary, AppRoute.expenses, AppRoute.profile];

/// Where [location] must be sent given the session, or null to stay; depends on nothing else.
/// PT: Para onde [location] deve ir dado o estado da sessão, ou null para ficar; não depende de mais nada.
/// [pendingVerification] (set by a successful register) pins a signed-in user to the verify screen.
/// PT: [pendingVerification] (ligada por um cadastro bem-sucedido) prende o usuário logado na tela de verificação.
/// Notes: docs/code-notes/app-core.md#redirectfor
String? redirectFor(SessionStatus status, Uri location, {bool pendingVerification = false}) {
  final path = location.path;
  final from = allowedFrom(location.queryParameters['from']);
  final onAuth =
      path == AppRoute.login.path ||
      path == AppRoute.register.path ||
      path == AppRoute.passwordReset.path;
  final onVerify = path == AppRoute.verifyEmail.path;
  final onSplash = path == AppRoute.splash.path;
  switch (status) {
    case SessionStatus.unknown:
      if (onSplash) return null;
      return _with(AppRoute.splash, _isTab(path) ? allowedFrom(path) : null);
    case SessionStatus.signedOut:
      if (onAuth) return null;
      return _with(AppRoute.login, onSplash ? from : (_isTab(path) ? allowedFrom(path) : null));
    case SessionStatus.signedIn:
      if (pendingVerification) return onVerify ? null : AppRoute.verifyEmail.path;
      if (onVerify) return null;
      if (onAuth || onSplash) return from ?? AppRoute.summary.path;
      return _isTab(path) ? null : AppRoute.summary.path;
  }
}

/// [raw] when it is an internal, allowlisted path (no scheme, host, `//`, query or fragment), else null.
/// PT: [raw] quando é um caminho interno da allowlist (sem scheme, host, `//`, query ou fragmento), senão null.
/// Notes: docs/code-notes/app-core.md#redirectfor
String? allowedFrom(String? raw) {
  if (raw == null || !raw.startsWith('/') || raw.startsWith('//') || raw.contains(r'\')) {
    return null;
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.hasScheme || uri.hasAuthority || uri.hasQuery || uri.hasFragment) {
    return null;
  }
  return _fromAllowlist.contains(uri.path) ? uri.path : null;
}

bool _isTab(String path) =>
    _tabRoots.any((tab) => path == tab.path || path.startsWith('${tab.path}/'));

String _with(AppRoute route, String? from) =>
    from == null ? route.path : Uri(path: route.path, queryParameters: {'from': from}).toString();

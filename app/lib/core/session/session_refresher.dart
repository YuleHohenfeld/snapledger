/// Exchanges the stored refresh token for a new access token, one exchange at a time.
/// PT: Troca o refresh token salvo por um novo access token, uma troca por vez.
/// Notes: docs/code-notes/app-core.md#apisessionrefresher
abstract interface class SessionRefresher {
  /// Never throws; on [SessionEnded] the tokens are already cleared.
  /// PT: Nunca lança; em [SessionEnded] os tokens já foram apagados.
  Future<RefreshOutcome> refresh();
}

/// What one refresh did to the session; callers switch on it exhaustively.
/// PT: O que um refresh fez com a sessão; quem chama faz um switch exaustivo sobre ele.
/// Notes: docs/code-notes/app-core.md#refreshoutcome
sealed class RefreshOutcome {
  const RefreshOutcome();
}

/// New tokens were saved; [accessToken] is the one to use now.
/// PT: Tokens novos foram salvos; [accessToken] é o que deve ser usado agora.
final class Refreshed extends RefreshOutcome {
  const Refreshed(this.accessToken);

  final String accessToken;

  @override
  String toString() => 'Refreshed(***)';
}

/// The server rejected the refresh token (or none was stored): this refresh cleared the session.
/// PT: O servidor rejeitou o refresh token (ou nenhum estava salvo): este refresh apagou a sessão.
final class SessionEnded extends RefreshOutcome {
  const SessionEnded();

  @override
  String toString() => 'SessionEnded()';
}

/// No new token, session untouched (offline, `500`, storage error, or a newer session took over).
/// PT: Sem token novo, sessão intacta (offline, `500`, erro de armazenamento, ou uma sessão mais nova assumiu).
final class TemporaryFailure extends RefreshOutcome {
  const TemporaryFailure();

  @override
  String toString() => 'TemporaryFailure()';
}

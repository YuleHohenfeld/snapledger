import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';

import 'in_memory_secure_store.dart';

/// A [SessionRefresher] that answers with [onRefresh] and counts its calls.
/// PT: Um [SessionRefresher] que responde com [onRefresh] e conta as chamadas.
class FakeSessionRefresher implements SessionRefresher {
  FakeSessionRefresher(this.onRefresh);

  Future<RefreshOutcome> Function() onRefresh;
  int calls = 0;

  @override
  Future<RefreshOutcome> refresh() {
    calls++;
    return onRefresh();
  }
}

/// A real [SessionNotifier] over an in-memory store, for screens that sign in.
/// PT: Um [SessionNotifier] real sobre um armazenamento em memória, para telas que fazem login.
({SessionNotifier session, TokenStore tokens, InMemorySecureStore store}) inMemorySession() {
  final store = InMemorySecureStore();
  final tokens = TokenStore(store);
  final session = SessionNotifier(
    tokens: tokens,
    refresher: FakeSessionRefresher(() async => const TemporaryFailure()),
  );
  return (session: session, tokens: tokens, store: store);
}

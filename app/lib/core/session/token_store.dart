import 'package:snapledger/core/storage/secure_store.dart';

/// Holds the session tokens: refresh token persisted, access token in memory only.
/// PT: Guarda os tokens da sessão: refresh token persistido, access token só em memória.
/// Notes: docs/code-notes/app-core.md#tokenstore
final class TokenStore {
  TokenStore(this._secure);

  static const refreshTokenKey = 'refresh_token';

  final SecureStore _secure;
  String? _accessToken;
  int _epoch = 0;
  int _writes = 0;
  bool _deletePending = false;

  /// Null on a cold start until the first refresh; never persisted.
  /// PT: Null num cold start até o primeiro refresh; nunca persistido.
  String? get accessToken => _accessToken;

  /// Increases on every [clear] and [save]; a refresh started before either must not save its result.
  /// PT: Aumenta a cada [clear] e [save]; um refresh iniciado antes de um deles não pode salvar o resultado.
  /// Notes: docs/code-notes/app-core.md#epoch
  int get epoch => _epoch;

  /// Null after a [clear] whose delete failed; may throw [SecureStoreException] when storage is unavailable.
  /// PT: Null depois de um [clear] cujo delete falhou; pode lançar [SecureStoreException] com o armazenamento indisponível.
  /// Notes: docs/code-notes/app-core.md#deletepending
  Future<String?> readRefreshToken() async {
    if (_deletePending) {
      try {
        await _deleteStored();
      } on SecureStoreException {
        // Still pending: the cleared token must never be read back.
        // PT: Ainda pendente: o token apagado nunca pode ser lido de volta.
      }
      return null;
    }
    return _secure.read(refreshTokenKey);
  }

  /// Starts a new session: persists the refresh token before exposing the access token.
  /// PT: Inicia uma sessão nova: persiste o refresh token antes de expor o access token.
  /// Notes: docs/code-notes/app-core.md#save
  Future<void> save({required String accessToken, required String refreshToken}) async {
    _epoch++;
    await _write(refreshToken);
    _accessToken = accessToken;
  }

  /// Like [save] for the same session, but only if the epoch is still [epoch]; returns whether it saved.
  /// PT: Como o [save] para a mesma sessão, mas só se o epoch ainda é [epoch]; diz se salvou.
  /// Notes: docs/code-notes/app-core.md#epoch
  Future<bool> saveIfEpoch(
    int epoch, {
    required String accessToken,
    required String refreshToken,
  }) async {
    if (epoch != _epoch) return false;
    final ticket = await _write(refreshToken);
    if (epoch != _epoch) {
      // A clear ran during the write: remove what was just written, unless a newer save wrote after it.
      // PT: Um clear rodou durante a escrita: remove o que foi escrito, a menos que um save mais novo tenha escrito depois.
      if (ticket == _writes) {
        try {
          await _deleteStored();
        } on SecureStoreException {
          // Marked pending: the next read retries the delete and returns null.
          // PT: Marcado como pendente: a próxima leitura tenta o delete de novo e devolve null.
        }
      }
      return false;
    }
    _accessToken = accessToken;
    return true;
  }

  /// Forgets both tokens; memory is cleared first, and a failed delete is retried by the next read.
  /// PT: Esquece os dois tokens; a memória é limpa antes, e um delete que falhou é refeito na próxima leitura.
  Future<void> clear() async {
    _epoch++;
    _accessToken = null;
    await _deleteStored();
  }

  // Returns this write's ticket; a higher [_writes] means a later write started after it.
  // PT: Devolve o número desta escrita; um [_writes] maior significa que outra escrita começou depois.
  Future<int> _write(String refreshToken) async {
    final ticket = ++_writes;
    await _secure.write(refreshTokenKey, refreshToken);
    // The stored value is now the new token, so the old one no longer needs deleting.
    // PT: O valor salvo agora é o token novo, então o antigo não precisa mais ser apagado.
    _deletePending = false;
    return ticket;
  }

  Future<void> _deleteStored() async {
    try {
      await _secure.delete(refreshTokenKey);
      _deletePending = false;
    } on SecureStoreException {
      _deletePending = true;
      rethrow;
    }
  }
}

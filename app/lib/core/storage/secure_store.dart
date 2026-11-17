/// The device keychain / keystore could not be used; the value was not saved or read.
/// PT: O keychain / keystore do aparelho não pôde ser usado; o valor não foi salvo nem lido.
final class SecureStoreException implements Exception {
  const SecureStoreException(this.operation);

  /// `read`, `write` or `delete`; never the key's value.
  /// PT: `read`, `write` ou `delete`; nunca o valor da chave.
  final String operation;

  @override
  String toString() => 'SecureStoreException($operation)';
}

/// Encrypted key-value storage for secrets; tests use an in-memory fake.
/// PT: Armazenamento chave-valor criptografado para segredos; os testes usam um fake em memória.
abstract interface class SecureStore {
  /// Null when absent or unreadable; throws [SecureStoreException] only for a transient failure.
  /// PT: Null quando ausente ou ilegível; lança [SecureStoreException] só em falha temporária.
  Future<String?> read(String key);

  /// Throws [SecureStoreException] when the value could not be saved.
  /// PT: Lança [SecureStoreException] quando o valor não pôde ser salvo.
  Future<void> write(String key, String value);

  /// Throws [SecureStoreException] when the value could not be removed.
  /// PT: Lança [SecureStoreException] quando o valor não pôde ser removido.
  Future<void> delete(String key);
}

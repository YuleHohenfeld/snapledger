import 'package:snapledger/core/storage/secure_store.dart';

/// A [SecureStore] over a map; the `fail*` flags simulate a keychain / keystore error.
/// PT: Um [SecureStore] sobre um mapa; as flags `fail*` simulam um erro do keychain / keystore.
class InMemorySecureStore implements SecureStore {
  final Map<String, String> values = {};
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;

  /// Runs at the start of every write, to interleave other work with it.
  /// PT: Roda no início de toda escrita, para intercalar outro trabalho com ela.
  Future<void> Function()? beforeWrite;

  /// Runs after a successful write stored its value.
  /// PT: Roda depois que uma escrita bem-sucedida guardou o valor.
  Future<void> Function()? afterWrite;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw const SecureStoreException('read');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    await beforeWrite?.call();
    if (failWrite) throw const SecureStoreException('write');
    values[key] = value;
    await afterWrite?.call();
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw const SecureStoreException('delete');
    values.remove(key);
  }
}

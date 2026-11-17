import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:snapledger/core/storage/secure_store.dart';

/// The only wrapper around flutter_secure_storage (Keychain on iOS, Keystore on Android).
/// PT: O único wrapper do flutter_secure_storage (Keychain no iOS, Keystore no Android).
/// Notes: docs/code-notes/app-core.md#devicesecurestore
final class DeviceSecureStore implements SecureStore {
  /// iOS: readable after the first unlock, never synced or restored to another device.
  /// PT: iOS: legível depois do primeiro desbloqueio, nunca sincronizado nem restaurado em outro aparelho.
  /// Notes: docs/code-notes/app-core.md#devicesecurestore
  const DeviceSecureStore()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
      );

  final FlutterSecureStorage _storage;

  // errSecInteractionNotAllowed: keychain still locked (for example right after a reboot).
  // PT: errSecInteractionNotAllowed: keychain ainda bloqueado (por exemplo logo após reiniciar).
  static const _keychainLocked = -25308;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (error) {
      if (error.details == _keychainLocked) throw const SecureStoreException('read');
      // Unreadable entry (for example a key lost after a restore): drop it, the user signs in again.
      // PT: Entrada ilegível (por exemplo chave perdida após um restore): descarta, o usuário entra de novo.
      try {
        await _storage.delete(key: key);
      } on PlatformException {
        // Best effort: the next read fails the same way and retries the delete.
        // PT: Melhor esforço: a próxima leitura falha igual e tenta o delete de novo.
      }
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException {
      throw const SecureStoreException('write');
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException {
      throw const SecureStoreException('delete');
    }
  }
}

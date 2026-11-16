import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/storage/device_secure_store.dart';
import 'package:snapledger/core/storage/secure_store.dart';

// The plugin's method channel, answered here instead of by the Keychain / Keystore.
// PT: O method channel do plugin, respondido aqui em vez de pelo Keychain / Keystore.
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'refresh_token';
  const store = DeviceSecureStore();
  late Map<String, String> data;
  late Map<String, PlatformException> errors;

  setUp(() {
    data = {key: 'fake-refresh-1'};
    errors = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (errors[call.method] case final error?) throw error;
      final args = (call.arguments as Map<Object?, Object?>).cast<String, Object?>();
      final k = args['key']! as String;
      return switch (call.method) {
        'read' => data[k],
        'write' => data[k] = args['value']! as String,
        'delete' => data.remove(k),
        _ => throw MissingPluginException(call.method),
      };
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));

  test('reads, writes and deletes through the plugin', () async {
    expect(await store.read(key), 'fake-refresh-1');

    await store.write(key, 'fake-refresh-2');
    expect(data[key], 'fake-refresh-2');

    await store.delete(key);
    expect(data, isEmpty);
  });

  test('a locked keychain is temporary: throws and keeps the entry', () async {
    errors['read'] = PlatformException(code: 'locked', details: -25308);

    await expectLater(
      store.read(key),
      throwsA(isA<SecureStoreException>().having((e) => e.operation, 'operation', 'read')),
    );
    expect(data[key], 'fake-refresh-1');
  });

  test('any other read error drops the unreadable entry and returns null', () async {
    errors['read'] = PlatformException(code: 'decrypt', details: 'bad padding');

    expect(await store.read(key), isNull);
    expect(data, isEmpty);
  });

  test('returns null even when dropping the unreadable entry fails too', () async {
    errors
      ..['read'] = PlatformException(code: 'decrypt')
      ..['delete'] = PlatformException(code: 'delete');

    expect(await store.read(key), isNull);
  });

  test('a write failure throws SecureStoreException(write)', () async {
    errors['write'] = PlatformException(code: 'write');

    await expectLater(
      store.write(key, 'fake-refresh-2'),
      throwsA(isA<SecureStoreException>().having((e) => e.operation, 'operation', 'write')),
    );
    expect(data[key], 'fake-refresh-1');
  });

  test('a delete failure throws SecureStoreException(delete)', () async {
    errors['delete'] = PlatformException(code: 'delete');

    await expectLater(
      store.delete(key),
      throwsA(isA<SecureStoreException>().having((e) => e.operation, 'operation', 'delete')),
    );
    expect(data[key], 'fake-refresh-1');
  });

  test('the exception never carries the stored value', () {
    expect(const SecureStoreException('read').toString(), isNot(contains('fake-refresh')));
  });
}

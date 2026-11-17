import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/config/app_config.dart';

void main() {
  Matcher refusedWith(ConfigError error) =>
      throwsA(isA<ConfigException>().having((e) => e.error, 'error', error));

  group('accepts', () {
    test('an https URL and strips trailing slashes', () {
      expect(AppConfig.parse('https://api.example.com/', isRelease: true).apiBaseUrl,
          'https://api.example.com');
      expect(AppConfig.parse('https://api.example.com///', isRelease: true).apiBaseUrl,
          'https://api.example.com');
    });

    test('an https URL with a port and a path prefix', () {
      expect(AppConfig.parse('https://example.com:8443/snap/', isRelease: true).apiBaseUrl,
          'https://example.com:8443/snap');
    });

    for (final host in ['localhost', '127.0.0.1', '10.0.2.2']) {
      test('http for the local host $host outside release builds', () {
        expect(AppConfig.parse('http://$host:8080', isRelease: false).apiBaseUrl,
            'http://$host:8080');
      });
    }
  });

  group('refuses', () {
    test('an empty or blank value', () {
      expect(() => AppConfig.parse('', isRelease: false), refusedWith(ConfigError.missing));
      expect(() => AppConfig.parse('   ', isRelease: false), refusedWith(ConfigError.missing));
    });

    test('surrounding whitespace', () {
      expect(() => AppConfig.parse(' https://api.example.com', isRelease: false),
          refusedWith(ConfigError.malformed));
    });

    test('a value that is not a URI', () {
      expect(() => AppConfig.parse('https://exa mple.com', isRelease: false),
          refusedWith(ConfigError.malformed));
    });

    test('a relative URL', () {
      expect(() => AppConfig.parse('api.example.com', isRelease: false),
          refusedWith(ConfigError.notAbsolute));
      expect(() => AppConfig.parse('/api', isRelease: false), refusedWith(ConfigError.notAbsolute));
    });

    test('a scheme other than http or https', () {
      expect(() => AppConfig.parse('ftp://api.example.com', isRelease: false),
          refusedWith(ConfigError.unsupportedScheme));
      expect(() => AppConfig.parse('file:///etc/hosts', isRelease: false),
          refusedWith(ConfigError.unsupportedScheme));
    });

    test('a URL without a host', () {
      expect(() => AppConfig.parse('https:///api', isRelease: false),
          refusedWith(ConfigError.missingHost));
    });

    test('credentials in the URL', () {
      expect(() => AppConfig.parse('https://user:secret@api.example.com', isRelease: false),
          refusedWith(ConfigError.userInfoNotAllowed));
    });

    test('a query or a fragment, even an empty one', () {
      for (final raw in [
        'https://api.example.com?x=1',
        'https://api.example.com/?',
        'https://api.example.com#top',
        'https://api.example.com/#',
      ]) {
        expect(() => AppConfig.parse(raw, isRelease: false),
            refusedWith(ConfigError.queryOrFragmentNotAllowed), reason: raw);
      }
    });

    test('http for a host that is not local', () {
      expect(() => AppConfig.parse('http://api.example.com', isRelease: false),
          refusedWith(ConfigError.insecureScheme));
      expect(() => AppConfig.parse('http://192.168.0.10:8080', isRelease: false),
          refusedWith(ConfigError.insecureScheme));
    });

    test('http even for localhost in a release build', () {
      for (final host in ['localhost', '127.0.0.1', '10.0.2.2']) {
        expect(() => AppConfig.parse('http://$host:8080', isRelease: true),
            refusedWith(ConfigError.insecureScheme), reason: host);
      }
    });
  });

  test('fromEnvironment refuses a build without API_BASE_URL', () {
    // `flutter test` runs without --dart-define, so the value is empty.
    // PT: O `flutter test` roda sem --dart-define, então o valor é vazio.
    expect(AppConfig.fromEnvironment, refusedWith(ConfigError.missing));
  });

  test('the exception carries a code, never the URL', () {
    expect(const ConfigException(ConfigError.insecureScheme).toString(),
        'ConfigException(insecureScheme)');
  });
}

import 'package:flutter/foundation.dart';

/// Why the API address was refused; a code for logic and tests, never text for the user.
/// PT: Por que o endereço da API foi recusado; um código para lógica e testes, nunca texto para o usuário.
enum ConfigError {
  missing,
  malformed,
  notAbsolute,
  unsupportedScheme,
  missingHost,
  userInfoNotAllowed,
  queryOrFragmentNotAllowed,
  insecureScheme,
}

/// Thrown when API_BASE_URL is missing or unsafe; the app shows a configuration screen.
/// PT: Lançada quando o API_BASE_URL falta ou é inseguro; o app mostra uma tela de configuração.
final class ConfigException implements Exception {
  const ConfigException(this.error);

  final ConfigError error;

  @override
  String toString() => 'ConfigException(${error.name})';
}

/// Validated build configuration; the only place in lib/ that knows a URL (hook rule D7).
/// PT: Configuração do build já validada; o único lugar em lib/ que conhece uma URL (regra D7).
/// Notes: docs/code-notes/app-core.md#appconfig
@immutable
final class AppConfig {
  const AppConfig._(this.apiBaseUrl);

  /// Reads `--dart-define=API_BASE_URL`; throws [ConfigException] when it is not acceptable.
  /// PT: Lê `--dart-define=API_BASE_URL`; lança [ConfigException] quando não é aceitável.
  factory AppConfig.fromEnvironment() =>
      AppConfig.parse(const String.fromEnvironment('API_BASE_URL'), isRelease: kReleaseMode);

  /// Validates [raw]; [isRelease] is a parameter so tests can check the release-only rule.
  /// PT: Valida [raw]; [isRelease] é parâmetro para os testes checarem a regra só de release.
  /// Notes: docs/code-notes/app-core.md#appconfig
  factory AppConfig.parse(String raw, {required bool isRelease}) {
    if (raw.trim().isEmpty) throw const ConfigException(ConfigError.missing);
    // Uri.tryParse would percent-encode a space inside the host instead of refusing it.
    // PT: O Uri.tryParse codificaria um espaço dentro do host em vez de recusá-lo.
    if (raw.contains(RegExp(r'\s'))) throw const ConfigException(ConfigError.malformed);
    final uri = Uri.tryParse(raw);
    if (uri == null) throw const ConfigException(ConfigError.malformed);
    if (!uri.hasScheme) throw const ConfigException(ConfigError.notAbsolute);
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const ConfigException(ConfigError.unsupportedScheme);
    }
    if (uri.host.isEmpty) throw const ConfigException(ConfigError.missingHost);
    if (uri.userInfo.isNotEmpty) throw const ConfigException(ConfigError.userInfoNotAllowed);
    if (uri.hasQuery || uri.hasFragment) {
      throw const ConfigException(ConfigError.queryOrFragmentNotAllowed);
    }
    if (uri.scheme == 'http' && (isRelease || !_localHosts.contains(uri.host))) {
      throw const ConfigException(ConfigError.insecureScheme);
    }
    var base = raw;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return AppConfig._(base);
  }

  // Hosts that only exist on the developer's machine: simulator, desktop, Android emulator.
  // PT: Hosts que só existem na máquina do desenvolvedor: simulador, desktop, emulador Android.
  static const _localHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

  /// Server root without a trailing slash, for example `https://api.example.com`.
  /// PT: Raiz do servidor sem barra no final, por exemplo `https://api.example.com`.
  final String apiBaseUrl;
}

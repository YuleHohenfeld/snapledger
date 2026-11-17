import 'package:flutter/foundation.dart';

/// The contract's `TokenResponse` (register, login, refresh); `toString` never shows a token.
/// PT: O `TokenResponse` do contrato (register, login, refresh); o `toString` nunca mostra um token.
/// Notes: docs/code-notes/app-core.md#tokenresponse
@immutable
final class TokenResponse {
  const TokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.refreshToken,
    required this.refreshExpiresIn,
  });

  /// Throws [FormatException] when a field is missing, empty or of the wrong type.
  /// PT: Lança [FormatException] quando um campo falta, está vazio ou tem o tipo errado.
  factory TokenResponse.fromJson(Map<String, Object?> json) => TokenResponse(
    accessToken: _token(json, 'accessToken'),
    tokenType: _token(json, 'tokenType'),
    expiresIn: _seconds(json, 'expiresIn'),
    refreshToken: _token(json, 'refreshToken'),
    refreshExpiresIn: _seconds(json, 'refreshExpiresIn'),
  );

  final String accessToken;
  final String tokenType;

  /// Lifetimes in seconds, as in the contract.
  /// PT: Durações em segundos, como no contrato.
  final int expiresIn;
  final String refreshToken;
  final int refreshExpiresIn;

  // The message names the field, never its value (it may be a token).
  // PT: A mensagem cita o campo, nunca o valor (ele pode ser um token).
  static String _token(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('TokenResponse.$field is missing or not a non-empty string');
  }

  static int _seconds(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is int && value > 0) return value;
    throw FormatException('TokenResponse.$field is missing or not a positive integer');
  }

  @override
  String toString() =>
      'TokenResponse(accessToken: ***, tokenType: $tokenType, expiresIn: $expiresIn, '
      'refreshToken: ***, refreshExpiresIn: $refreshExpiresIn)';
}

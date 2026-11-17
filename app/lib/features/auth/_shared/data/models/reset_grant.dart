import 'package:flutter/foundation.dart';

/// The `200` of `POST /auth/password-reset/verify`: a short-lived token that allows one new password.
/// PT: O `200` do `POST /auth/password-reset/verify`: um token de curta duração que permite uma nova senha.
/// Notes: docs/code-notes/app-auth.md#resetgrant
@immutable
final class ResetGrant {
  const ResetGrant({required this.token, required this.expiresIn});

  /// Throws [FormatException] naming the missing or malformed field, never its value.
  /// PT: Lança [FormatException] citando o campo ausente ou malformado, nunca o valor dele.
  factory ResetGrant.fromJson(Map<String, Object?> json) {
    final token = json['resetToken'];
    final expiresIn = json['expiresIn'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('ResetGrant.resetToken is missing or not a string');
    }
    if (expiresIn is! int) {
      throw const FormatException('ResetGrant.expiresIn is missing or not an integer');
    }
    return ResetGrant(token: token, expiresIn: expiresIn);
  }

  /// A secret: lives only in the ViewModel's memory (never URL, route extra, storage or log).
  /// PT: Um segredo: vive só na memória do ViewModel (nunca URL, extra de rota, storage ou log).
  final String token;

  /// Seconds the token stays valid.
  /// PT: Segundos de validade do token.
  final int expiresIn;

  @override
  String toString() => 'ResetGrant(token: ***, expiresIn: $expiresIn)';
}

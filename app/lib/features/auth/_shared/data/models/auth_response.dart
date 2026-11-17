import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/token_response.dart';
import 'package:snapledger/features/profile/_shared/data/models/user_model.dart';

/// The `201` of register and the `200` of login: the user plus a new token pair.
/// PT: O `201` do cadastro e o `200` do login: o usuário mais um novo par de tokens.
/// Notes: docs/code-notes/app-auth.md#authresponse
@immutable
final class AuthResponse {
  const AuthResponse({required this.user, required this.tokens});

  /// Throws [FormatException] naming the missing or malformed field, never its value.
  /// PT: Lança [FormatException] citando o campo ausente ou malformado, nunca o valor dele.
  factory AuthResponse.fromJson(Map<String, Object?> json) => AuthResponse(
    user: UserModel.fromJson(_object(json, 'user')),
    tokens: TokenResponse.fromJson(_object(json, 'tokens')),
  );

  final UserModel user;
  final TokenResponse tokens;

  static Map<String, Object?> _object(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is Map<String, Object?>) return value;
    throw FormatException('AuthResponse.$field is missing or not a JSON object');
  }

  // Both parts mask their own secrets and personal data.
  // PT: As duas partes mascaram os próprios segredos e dados pessoais.
  @override
  String toString() => 'AuthResponse(user: $user, tokens: $tokens)';
}

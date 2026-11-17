import 'package:flutter/foundation.dart';

/// The contract's `UserResponse`; `toString` shows only the id (name and email are personal data).
/// PT: O `UserResponse` do contrato; o `toString` mostra só o id (nome e email são dados pessoais).
/// Notes: docs/code-notes/app-auth.md#usermodel
@immutable
final class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.currency,
    required this.createdAt,
    required this.emailVerified,
  });

  /// Throws [FormatException] naming the missing or malformed field, never its value.
  /// PT: Lança [FormatException] citando o campo ausente ou malformado, nunca o valor dele.
  factory UserModel.fromJson(Map<String, Object?> json) => UserModel(
    id: _text(json, 'id'),
    name: _text(json, 'name'),
    email: _text(json, 'email'),
    currency: _text(json, 'currency'),
    createdAt: _timestamp(json, 'createdAt'),
    emailVerified: _flag(json, 'emailVerified'),
  );

  final String id;
  final String name;
  final String email;

  /// ISO 4217 code (`BRL`, `USD`...). PT: Código ISO 4217 (`BRL`, `USD`...).
  final String currency;
  final DateTime createdAt;

  /// True once the user proved access to the email with a code.
  /// PT: Verdadeiro quando o usuário provou acesso ao email com um código.
  final bool emailVerified;

  // Strict: a missing or non-bool value is a contract break, never "not verified".
  // PT: Estrito: valor ausente ou não booleano quebra o contrato, nunca vira "não verificado".
  static bool _flag(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is bool) return value;
    throw FormatException('UserModel.$field is missing or not a boolean');
  }

  static String _text(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('UserModel.$field is missing or not a non-empty string');
  }

  // DateTime.parse would put the raw value in its message, so the error is rebuilt with the name only.
  // PT: O DateTime.parse colocaria o valor bruto na mensagem, então o erro é refeito só com o nome.
  static DateTime _timestamp(Map<String, Object?> json, String field) {
    final value = json[field];
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed != null) return parsed;
    throw FormatException('UserModel.$field is missing or not an ISO-8601 timestamp');
  }

  @override
  bool operator ==(Object other) =>
      other is UserModel &&
      other.id == id &&
      other.name == name &&
      other.email == email &&
      other.currency == currency &&
      other.createdAt == createdAt &&
      other.emailVerified == emailVerified;

  @override
  int get hashCode => Object.hash(id, name, email, currency, createdAt, emailVerified);

  @override
  String toString() => 'UserModel(id: $id, name: ***, email: ***, currency: $currency)';
}

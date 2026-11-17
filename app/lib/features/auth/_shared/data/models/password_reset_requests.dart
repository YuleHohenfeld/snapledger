import 'package:flutter/foundation.dart';

/// Body of `POST /auth/password-reset`; the email is personal data, so `toString` hides it.
/// PT: Corpo do `POST /auth/password-reset`; o email é dado pessoal, então o `toString` o esconde.
/// Notes: docs/code-notes/app-auth.md#requests
@immutable
final class PasswordResetRequest {
  const PasswordResetRequest({required this.email});

  final String email;

  Map<String, Object?> toJson() => {'email': email};

  @override
  String toString() => 'PasswordResetRequest(email: ***)';
}

/// Body of `POST /auth/password-reset/confirm`; the code and the new password are secrets.
/// PT: Corpo do `POST /auth/password-reset/confirm`; o código e a nova senha são segredos.
/// Notes: docs/code-notes/app-auth.md#requests
@immutable
final class PasswordResetConfirmRequest {
  const PasswordResetConfirmRequest({
    required this.email,
    required this.code,
    required this.newPassword,
  });

  final String email;
  final String code;
  final String newPassword;

  Map<String, Object?> toJson() => {'email': email, 'code': code, 'newPassword': newPassword};

  @override
  String toString() => 'PasswordResetConfirmRequest(email: ***, code: ***, newPassword: ***)';
}

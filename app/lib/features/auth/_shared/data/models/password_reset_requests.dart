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

/// Body of `POST /auth/password-reset/verify`; the email and the code are secrets of the flow.
/// PT: Corpo do `POST /auth/password-reset/verify`; o email e o código são segredos do fluxo.
/// Notes: docs/code-notes/app-auth.md#requests
@immutable
final class PasswordResetVerifyRequest {
  const PasswordResetVerifyRequest({required this.email, required this.code});

  final String email;
  final String code;

  Map<String, Object?> toJson() => {'email': email, 'code': code};

  @override
  String toString() => 'PasswordResetVerifyRequest(email: ***, code: ***)';
}

/// Body of `POST /auth/password-reset/confirm`; the reset token and the new password are secrets.
/// PT: Corpo do `POST /auth/password-reset/confirm`; o reset token e a nova senha são segredos.
/// Notes: docs/code-notes/app-auth.md#requests
@immutable
final class PasswordResetConfirmRequest {
  const PasswordResetConfirmRequest({required this.resetToken, required this.newPassword});

  final String resetToken;
  final String newPassword;

  Map<String, Object?> toJson() => {'resetToken': resetToken, 'newPassword': newPassword};

  @override
  String toString() => 'PasswordResetConfirmRequest(resetToken: ***, newPassword: ***)';
}

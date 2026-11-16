import 'package:flutter/foundation.dart';

/// Body of `POST /auth/login`; `toString` never shows the email or the password.
/// PT: Corpo do `POST /auth/login`; o `toString` nunca mostra o email nem a senha.
/// Notes: docs/code-notes/app-auth.md#requests
@immutable
final class LoginRequest {
  const LoginRequest({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, Object?> toJson() => {'email': email, 'password': password};

  @override
  String toString() => 'LoginRequest(email: ***, password: ***)';
}

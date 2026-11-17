import 'package:flutter/foundation.dart';

/// Body of `POST /auth/register`; `currency` is omitted so the server default (BRL) applies.
/// PT: Corpo do `POST /auth/register`; `currency` é omitida para valer o padrão do servidor (BRL).
/// Notes: docs/code-notes/app-auth.md#requests
@immutable
final class RegisterRequest {
  const RegisterRequest({required this.name, required this.email, required this.password});

  final String name;
  final String email;
  final String password;

  Map<String, Object?> toJson() => {'name': name, 'email': email, 'password': password};

  // Name and email are personal data, the password a secret: none of them is printed.
  // PT: Nome e email são dados pessoais, a senha um segredo: nenhum deles é impresso.
  @override
  String toString() => 'RegisterRequest(name: ***, email: ***, password: ***)';
}

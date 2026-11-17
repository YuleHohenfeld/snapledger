import 'dart:convert';

/// Why a login or register field was refused on the device; the View turns it into localized text.
/// PT: Por que um campo de login ou cadastro foi recusado no aparelho; a View o transforma em texto traduzido.
/// Notes: docs/code-notes/app-auth.md#authvalidators
enum AuthFieldError {
  required,
  emailInvalid,
  emailTooLong,
  nameTooLong,
  nameInvalidChars,
  passwordTooShort,
  passwordTooLong,
  codeInvalid,
}

// Limits copied from docs/api-contract.md (register and login); the API stays the authority.
// PT: Limites copiados do docs/api-contract.md (register e login); a API continua sendo a autoridade.
const nameMaxCodePoints = 80;
const emailMaxLength = 254;
const passwordMinBytes = 8;
const passwordMaxBytes = 72;

// Control (Cc), format (Cf) and lone surrogate (Cs) code points, like the API's NoControlCharacters.
// PT: Code points de controle (Cc), formatação (Cf) e surrogate sozinho (Cs), como o NoControlCharacters da API.
final _invisible = RegExp(r'[\p{Cc}\p{Cf}\p{Cs}]', unicode: true);

/// Register name: ends trimmed, 1–80 code points (an emoji is one), no invisible characters.
/// PT: Nome do cadastro: pontas aparadas, 1–80 code points (um emoji é um), sem caracteres invisíveis.
/// Notes: docs/code-notes/app-auth.md#validatename
AuthFieldError? validateName(String? value) {
  final name = (value ?? '').trim();
  if (name.isEmpty) return AuthFieldError.required;
  if (_invisible.hasMatch(name)) return AuthFieldError.nameInvalidChars;
  if (name.runes.length > nameMaxCodePoints) return AuthFieldError.nameTooLong;
  return null;
}

/// Email: only the ends are trimmed; printable ASCII, one `@` with text on both sides, at most 254.
/// PT: Email: só as pontas são aparadas; ASCII imprimível, um `@` com texto dos dois lados, no máximo 254.
/// Notes: docs/code-notes/app-auth.md#validateemail
AuthFieldError? validateEmail(String? value) {
  final email = (value ?? '').trim();
  if (email.isEmpty) return AuthFieldError.required;
  if (email.length > emailMaxLength) return AuthFieldError.emailTooLong;
  // 0x21–0x7E excludes every space and every accent, like the API's `[!-~]+`.
  // PT: 0x21–0x7E exclui todo espaço e todo acento, como o `[!-~]+` da API.
  if (email.codeUnits.any((unit) => unit < 0x21 || unit > 0x7E)) {
    return AuthFieldError.emailInvalid;
  }
  final at = email.indexOf('@');
  if (at <= 0 || at == email.length - 1 || email.indexOf('@', at + 1) != -1) {
    return AuthFieldError.emailInvalid;
  }
  return null;
}

/// Register password: not blank, 8–72 bytes in UTF-8 (`é` is 2 bytes, an emoji 4); never trimmed.
/// PT: Senha do cadastro: não vazia, 8–72 bytes em UTF-8 (`é` tem 2 bytes, um emoji 4); nunca aparada.
/// Notes: docs/code-notes/app-auth.md#validatepassword
AuthFieldError? validateRegisterPassword(String? value) {
  final password = value ?? '';
  if (password.trim().isEmpty) return AuthFieldError.required;
  final bytes = utf8.encode(password).length;
  if (bytes < passwordMinBytes) return AuthFieldError.passwordTooShort;
  if (bytes > passwordMaxBytes) return AuthFieldError.passwordTooLong;
  return null;
}

/// Email code: exactly 6 ASCII digits (full-width and other Unicode digits are refused); never trimmed.
/// PT: Código do email: exatamente 6 dígitos ASCII (dígitos full-width e outros Unicode são recusados); nunca aparado.
/// Notes: docs/code-notes/app-auth.md#codefield
AuthFieldError? validateCode(String? value) {
  final code = value ?? '';
  if (code.isEmpty) return AuthFieldError.required;
  return _sixAsciiDigits.hasMatch(code) ? null : AuthFieldError.codeInvalid;
}

// Explicit [0-9]: `\d` could match other Unicode digits in some engines.
// PT: [0-9] explícito: `\d` poderia casar outros dígitos Unicode em alguns motores.
final _sixAsciiDigits = RegExp(r'^[0-9]{6}$');

/// Login password: not blank and at most 72 bytes; no minimum, so login never reveals the policy.
/// PT: Senha do login: não vazia e no máximo 72 bytes; sem mínimo, para o login nunca revelar a política.
/// Notes: docs/code-notes/app-auth.md#validatepassword
AuthFieldError? validateLoginPassword(String? value) {
  final password = value ?? '';
  if (password.trim().isEmpty) return AuthFieldError.required;
  if (utf8.encode(password).length > passwordMaxBytes) return AuthFieldError.passwordTooLong;
  return null;
}

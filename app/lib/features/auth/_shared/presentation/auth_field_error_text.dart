import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The localized text of a device-side field error, or null when the field is valid.
/// PT: O texto traduzido de um erro de campo detectado no aparelho, ou null quando o campo é válido.
/// Notes: docs/code-notes/app-auth.md#pages
String? authFieldErrorText(AppLocalizations l10n, AuthFieldError? error) => switch (error) {
  null => null,
  AuthFieldError.required => l10n.validationRequired,
  AuthFieldError.emailInvalid => l10n.validationEmailInvalid,
  AuthFieldError.emailTooLong => l10n.validationEmailTooLong(emailMaxLength),
  AuthFieldError.nameTooLong => l10n.validationNameTooLong(nameMaxCodePoints),
  AuthFieldError.nameInvalidChars => l10n.validationNameInvalidChars,
  AuthFieldError.passwordTooShort => l10n.validationPasswordTooShort(passwordMinBytes),
  AuthFieldError.passwordTooLong => l10n.validationPasswordTooLong,
};

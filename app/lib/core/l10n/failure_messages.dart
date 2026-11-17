import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/storage/secure_store.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The localized text for a failure, or null when there is none or the form fields already show it.
/// PT: O texto traduzido de uma falha, ou null quando não há falha ou os campos do formulário já a mostram.
/// Notes: docs/code-notes/app-core.md#failuremessages
String? failureMessage(
  AppLocalizations l10n,
  Object? failure, {
  Set<String> knownFields = const {},
}) => switch (failure) {
  null => null,
  NetworkFailure() => l10n.errorNetwork,
  ProblemFailure(type: ProblemType.validationError, :final fieldErrors)
      when fieldErrors.isNotEmpty && fieldErrors.every(knownFields.contains) =>
    null,
  ProblemFailure(type: ProblemType.validationError) => l10n.errorValidation,
  // Shown under the email field instead (fieldErrorMessage) when the form has one.
  // PT: Aparece sob o campo de email (fieldErrorMessage) quando o formulário tem um.
  ProblemFailure(type: ProblemType.emailAlreadyRegistered) when knownFields.contains('email') =>
    null,
  // Shown under the code field instead when the form has one.
  // PT: Aparece sob o campo do código quando o formulário tem um.
  ProblemFailure(type: ProblemType.invalidCode) when knownFields.contains('code') => null,
  ProblemFailure(type: ProblemType.invalidCredentials) => l10n.errorInvalidCredentials,
  ProblemFailure(type: ProblemType.invalidCode) => l10n.errorInvalidCode,
  ProblemFailure(type: ProblemType.invalidResetToken) => l10n.errorResetSessionExpired,
  ProblemFailure(type: ProblemType.tooManyRequests) => l10n.errorTooManyRequests,
  ProblemFailure(type: ProblemType.emailAlreadyRegistered) => l10n.errorEmailTaken,
  ProblemFailure(type: ProblemType.unauthorized) => l10n.errorUnauthorized,
  ProblemFailure(type: ProblemType.internalError, :final errorId?) => l10n.errorUnexpectedWithId(
    errorId,
  ),
  SecureStoreException() => l10n.errorStorage,
  _ => l10n.errorUnexpected,
};

/// The message under [field] when the server rejected it, else null; server text is never shown.
/// PT: A mensagem sob [field] quando o servidor o rejeitou, senão null; texto do servidor nunca aparece.
/// Notes: docs/code-notes/app-core.md#failuremessages
String? fieldErrorMessage(AppLocalizations l10n, Object? failure, String field) =>
    switch (failure) {
      ProblemFailure(type: ProblemType.validationError, :final fieldErrors)
          when fieldErrors.contains(field) =>
        l10n.validationFieldInvalid,
      ProblemFailure(type: ProblemType.emailAlreadyRegistered) when field == 'email' =>
        l10n.errorEmailTaken,
      ProblemFailure(type: ProblemType.invalidCode) when field == 'code' => l10n.codeWrong,
      _ => null,
    };

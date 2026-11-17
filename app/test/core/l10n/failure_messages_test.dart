import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/core/storage/secure_store.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  ProblemFailure problem(ProblemType type, {List<String> fields = const [], String? errorId}) =>
      ProblemFailure(status: 400, type: type, fieldErrors: fields, errorId: errorId);

  test('maps each failure to its message', () {
    expect(failureMessage(l10n, const NetworkFailure()), l10n.errorNetwork);
    expect(
      failureMessage(l10n, problem(ProblemType.invalidCredentials)),
      l10n.errorInvalidCredentials,
    );
    expect(failureMessage(l10n, problem(ProblemType.emailAlreadyRegistered)), l10n.errorEmailTaken);
    expect(failureMessage(l10n, problem(ProblemType.unauthorized)), l10n.errorUnauthorized);
    expect(failureMessage(l10n, const SecureStoreException('write')), l10n.errorStorage);
  });

  test('invalid-code and too-many-requests have their own text; a code form shows the first inline', () {
    expect(failureMessage(l10n, problem(ProblemType.invalidCode)), l10n.errorInvalidCode);
    expect(
      failureMessage(l10n, problem(ProblemType.tooManyRequests)),
      l10n.errorTooManyRequests,
    );
    expect(
      failureMessage(l10n, problem(ProblemType.invalidCode), knownFields: const {'code'}),
      isNull,
    );
    expect(
      fieldErrorMessage(l10n, problem(ProblemType.invalidCode), 'code'),
      l10n.errorInvalidCode,
    );
    expect(fieldErrorMessage(l10n, problem(ProblemType.invalidCode), 'email'), isNull);
  });

  test('a 500 shows its errorId for support, or the generic text without one', () {
    expect(
      failureMessage(l10n, problem(ProblemType.internalError, errorId: '3f9a1c2e')),
      l10n.errorUnexpectedWithId('3f9a1c2e'),
    );
    expect(failureMessage(l10n, problem(ProblemType.internalError)), l10n.errorUnexpected);
  });

  test('every other type, unknown and foreign errors get the generic text', () {
    for (final type in ProblemType.values.where(
      (t) => !{
        ProblemType.validationError,
        ProblemType.invalidCredentials,
        ProblemType.emailAlreadyRegistered,
        ProblemType.unauthorized,
        ProblemType.invalidCode,
        ProblemType.tooManyRequests,
        ProblemType.internalError,
      }.contains(t),
    )) {
      expect(failureMessage(l10n, problem(type)), l10n.errorUnexpected, reason: type.name);
    }
    expect(failureMessage(l10n, StateError('bug')), l10n.errorUnexpected);
  });

  test('no failure, no message', () {
    expect(failureMessage(l10n, null), isNull);
  });

  group('validation-error', () {
    final failure = problem(ProblemType.validationError, fields: ['email', 'password']);

    test('shows validationFieldInvalid under each rejected field', () {
      expect(fieldErrorMessage(l10n, failure, 'email'), l10n.validationFieldInvalid);
      expect(fieldErrorMessage(l10n, failure, 'password'), l10n.validationFieldInvalid);
      expect(fieldErrorMessage(l10n, failure, 'name'), isNull);
    });

    test('needs no general message when the form shows every rejected field', () {
      expect(failureMessage(l10n, failure, knownFields: {'email', 'password', 'name'}), isNull);
    });

    test('falls back to errorValidation when a field is not on the form', () {
      expect(failureMessage(l10n, failure, knownFields: {'email'}), l10n.errorValidation);
      expect(failureMessage(l10n, failure), l10n.errorValidation);
      expect(
        failureMessage(l10n, problem(ProblemType.validationError), knownFields: {'email'}),
        l10n.errorValidation,
      );
    });

    test('other failures never produce a field message', () {
      expect(fieldErrorMessage(l10n, const NetworkFailure(), 'email'), isNull);
      expect(fieldErrorMessage(l10n, null, 'email'), isNull);
    });
  });

  group('email-already-registered', () {
    final failure = problem(ProblemType.emailAlreadyRegistered);

    test('goes under the email field when the form has one', () {
      expect(fieldErrorMessage(l10n, failure, 'email'), l10n.errorEmailTaken);
      expect(failureMessage(l10n, failure, knownFields: {'name', 'email', 'password'}), isNull);
    });

    test('stays a general message when the form has no email field', () {
      expect(fieldErrorMessage(l10n, failure, 'name'), isNull);
      expect(failureMessage(l10n, failure, knownFields: {'name'}), l10n.errorEmailTaken);
    });
  });

  test('never shows the server title, detail or field messages', () {
    final failure = ProblemFailure.fromResponse(400, {
      'type': 'urn:snapledger:problem:validation-error',
      'title': 'SERVER-TITLE',
      'detail': 'SERVER-DETAIL',
      'errors': [
        {'field': 'x', 'message': 'SERVER-MSG'},
      ],
    });
    final shown = [
      failureMessage(l10n, failure),
      failureMessage(l10n, failure, knownFields: {'x'}),
      fieldErrorMessage(l10n, failure, 'x'),
    ];

    expect(shown.first, l10n.errorValidation);
    expect(shown.last, l10n.validationFieldInvalid);
    for (final text in shown.nonNulls) {
      for (final server in ['SERVER-TITLE', 'SERVER-DETAIL', 'SERVER-MSG']) {
        expect(text, isNot(contains(server)));
      }
    }
  });
}

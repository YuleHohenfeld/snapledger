import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';

void main() {
  const contractSlugs = {
    'validation-error': ProblemType.validationError,
    'unauthorized': ProblemType.unauthorized,
    'invalid-credentials': ProblemType.invalidCredentials,
    'invalid-refresh-token': ProblemType.invalidRefreshToken,
    'forbidden': ProblemType.forbidden,
    'default-category-read-only': ProblemType.defaultCategoryReadOnly,
    'not-found': ProblemType.notFound,
    'method-not-allowed': ProblemType.methodNotAllowed,
    'not-acceptable': ProblemType.notAcceptable,
    'email-already-registered': ProblemType.emailAlreadyRegistered,
    'category-name-taken': ProblemType.categoryNameTaken,
    'category-in-use': ProblemType.categoryInUse,
    'unsupported-media-type': ProblemType.unsupportedMediaType,
    'invalid-code': ProblemType.invalidCode,
    'invalid-reset-token': ProblemType.invalidResetToken,
    'too-many-requests': ProblemType.tooManyRequests,
    'internal-error': ProblemType.internalError,
  };

  test('knows every slug of the contract error table and nothing more', () {
    expect(contractSlugs, hasLength(17));
    for (final entry in contractSlugs.entries) {
      expect(ProblemType.fromType('urn:snapledger:problem:${entry.key}'), entry.value,
          reason: entry.key);
    }
    // Plus `unknown`. PT: Mais o `unknown`.
    expect(ProblemType.values.length, contractSlugs.length + 1);
  });

  test('maps about:blank, unknown slugs and odd values to unknown', () {
    for (final type in <Object?>[
      'about:blank',
      'urn:snapledger:problem:rate-limited',
      'urn:snapledger:problem:',
      'urn:other:problem:not-found',
      'not-found',
      null,
      42,
    ]) {
      expect(ProblemType.fromType(type), ProblemType.unknown, reason: '$type');
    }
  });

  test('reads field names, never the server messages', () {
    final failure = ProblemFailure.fromResponse(400, {
      'type': 'urn:snapledger:problem:validation-error',
      'status': 400,
      'errors': [
        {'field': 'email', 'message': 'must be a well-formed email address'},
        {'field': 'password', 'message': 'size must be between 8 and 72'},
        {'message': 'no field'},
        'not an object',
      ],
    });

    expect(failure.status, 400);
    expect(failure.type, ProblemType.validationError);
    expect(failure.fieldErrors, ['email', 'password']);
    expect(failure.errorId, isNull);
  });

  test('reads the errorId of a 500', () {
    final failure = ProblemFailure.fromResponse(500, {
      'type': 'urn:snapledger:problem:internal-error',
      'status': 500,
      'errorId': '3f9a1c2e',
    });

    expect(failure.type, ProblemType.internalError);
    expect(failure.errorId, '3f9a1c2e');
  });

  test('decodes a raw problem+json string', () {
    final failure = ProblemFailure.fromResponse(
      409,
      jsonEncode({'type': 'urn:snapledger:problem:email-already-registered', 'status': 409}),
    );

    expect(failure.type, ProblemType.emailAlreadyRegistered);
  });

  test('keeps the status when the body is not a JSON object', () {
    for (final body in <Object?>[null, '', '<html>bad gateway</html>', '[1,2]', '{broken', 7]) {
      final failure = ProblemFailure.fromResponse(403, body);
      expect(failure.status, 403, reason: '$body');
      expect(failure.type, ProblemType.unknown, reason: '$body');
      expect(failure.fieldErrors, isEmpty);
    }
  });

  test('ignores a non-list errors and a non-string errorId', () {
    final failure = ProblemFailure.fromResponse(400, {
      'type': 'urn:snapledger:problem:validation-error',
      'errors': {'field': 'email'},
      'errorId': 12,
    });

    expect(failure.fieldErrors, isEmpty);
    expect(failure.errorId, isNull);
  });
}

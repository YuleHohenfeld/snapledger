import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/api/api_stack.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/features/auth/_shared/data/models/login_request.dart';
import 'package:snapledger/features/auth/_shared/data/models/password_reset_requests.dart';
import 'package:snapledger/features/auth/_shared/data/models/register_request.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';

import '../../../../../support/fake_http_adapter.dart';
import '../../../../../support/json_fixtures.dart';

void main() {
  late FakeHttpAdapter adapter;
  late ResponseBody Function(RequestOptions options) answer;
  late ApiAuthRepository repository;

  setUp(() {
    answer = (_) => jsonBody(200, fakeAuthJson(1));
    adapter = FakeHttpAdapter((options) async => answer(options));
    final config = AppConfig.parse('https://api.test', isRelease: true);
    repository = ApiAuthRepository(
      ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = adapter),
    );
  });

  Map<String, Object?> sentBody() =>
      jsonDecode(jsonEncode(adapter.requests.single.data)) as Map<String, Object?>;

  const register = RegisterRequest(
    name: 'Ana Souza',
    email: 'ana@example.com',
    password: 'fake-password',
  );
  const login = LoginRequest(email: 'ana@example.com', password: 'fake-password');

  group('register', () {
    test('posts name, email and password to /auth/register, without currency', () async {
      answer = (_) => jsonBody(201, fakeAuthJson(1));

      await repository.register(register);

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.toString(), 'https://api.test/api/v1/auth/register');
      expect(sentBody(), {
        'name': 'Ana Souza',
        'email': 'ana@example.com',
        'password': 'fake-password',
      });
      expect(sentBody().containsKey('currency'), isFalse);
    });

    test('parses the user and the tokens', () async {
      answer = (_) => jsonBody(201, fakeAuthJson(7));

      final response = await repository.register(register);

      expect(response.user.id, '6f1c2a4e-8b0d-4c39-9a51-2f7e0d3b9c11');
      expect(response.user.name, 'Ana Souza');
      expect(response.user.email, 'ana@example.com');
      expect(response.user.currency, 'BRL');
      expect(response.user.createdAt, DateTime.utc(2026, 11, 10, 14, 3, 22));
      expect(response.tokens.accessToken, 'fake-access-7');
      expect(response.tokens.refreshToken, 'fake-refresh-7');
    });

    test('409 email-already-registered becomes a typed failure', () async {
      answer = (_) => problemBody(409, 'email-already-registered');

      await expectLater(
        repository.register(register),
        throwsA(
          isA<ProblemFailure>()
              .having((f) => f.status, 'status', 409)
              .having((f) => f.type, 'type', ProblemType.emailAlreadyRegistered),
        ),
      );
    });

    test('400 validation-error keeps the rejected field names', () async {
      answer = (_) => validationProblemBody(['name', 'password']);

      await expectLater(
        repository.register(register),
        throwsA(
          isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.validationError).having(
            (f) => f.fieldErrors,
            'fieldErrors',
            ['name', 'password'],
          ),
        ),
      );
    });

    test('a 201 body without the promised fields is a ProblemFailure, not a crash', () async {
      answer = (_) => jsonBody(201, {'user': fakeUserJson()});

      await expectLater(
        repository.register(register),
        throwsA(
          isA<ProblemFailure>()
              .having((f) => f.status, 'status', 201)
              .having((f) => f.type, 'type', ProblemType.unknown),
        ),
      );
    });
  });

  group('login', () {
    test('posts email and password to /auth/login and parses the answer', () async {
      final response = await repository.login(login);

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.toString(), 'https://api.test/api/v1/auth/login');
      expect(sentBody(), {'email': 'ana@example.com', 'password': 'fake-password'});
      expect(response.tokens.accessToken, 'fake-access-1');
    });

    test('401 invalid-credentials becomes a typed failure', () async {
      answer = (_) => problemBody(401, 'invalid-credentials');

      await expectLater(
        repository.login(login),
        throwsA(
          isA<ProblemFailure>()
              .having((f) => f.status, 'status', 401)
              .having((f) => f.type, 'type', ProblemType.invalidCredentials),
        ),
      );
    });

    test('400 validation-error keeps the rejected field names', () async {
      answer = (_) => validationProblemBody(['email']);

      await expectLater(
        repository.login(login),
        throwsA(isA<ProblemFailure>().having((f) => f.fieldErrors, 'fieldErrors', ['email'])),
      );
    });

    test('a malformed 200 body is a ProblemFailure', () async {
      answer = (_) => jsonBody(200, {'user': fakeUserJson(), 'tokens': 'nope'});

      await expectLater(
        repository.login(login),
        throwsA(isA<ProblemFailure>().having((f) => f.status, 'status', 200)),
      );
    });

    test('no network becomes a NetworkFailure', () async {
      final offline = FakeHttpAdapter(
        (options) async =>
            throw DioException.connectionError(requestOptions: options, reason: 'offline'),
      );
      final config = AppConfig.parse('https://api.test', isRelease: true);
      final offlineRepository = ApiAuthRepository(
        ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = offline),
      );

      await expectLater(offlineRepository.login(login), throwsA(isA<NetworkFailure>()));
    });
  });

  group('logout', () {
    test('posts the refresh token to /auth/logout and accepts 204', () async {
      answer = (_) => textBody(204, '');

      await repository.logout('fake-refresh-1');

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.toString(), 'https://api.test/api/v1/auth/logout');
      expect(sentBody(), {'refreshToken': 'fake-refresh-1'});
    });

    test('400 validation-error propagates as a ProblemFailure', () async {
      answer = (_) => validationProblemBody(['refreshToken']);

      await expectLater(repository.logout(''), throwsA(isA<ProblemFailure>()));
    });
  });

  group('password reset', () {
    const request = PasswordResetRequest(email: 'ana@example.com');
    const verify = PasswordResetVerifyRequest(email: 'ana@example.com', code: '042917');
    const confirm = PasswordResetConfirmRequest(
      resetToken: 'fake-reset-token',
      newPassword: 'fake-new-password',
    );

    test('requests a code with POST /auth/password-reset and accepts 202', () async {
      answer = (_) => textBody(202, '');

      await repository.requestPasswordReset(request);

      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.uri.toString(), 'https://api.test/api/v1/auth/password-reset');
      expect(sentBody(), {'email': 'ana@example.com'});
    });

    test('a 429 on the request is a too-many-requests failure', () async {
      answer = (_) => problemBody(429, 'too-many-requests');

      await expectLater(
        repository.requestPasswordReset(request),
        throwsA(
          isA<ProblemFailure>()
              .having((f) => f.status, 'status', 429)
              .having((f) => f.type, 'type', ProblemType.tooManyRequests),
        ),
      );
    });

    test('confirms with POST /auth/password-reset/confirm and accepts 204', () async {
      answer = (_) => textBody(204, '');

      await repository.confirmPasswordReset(confirm);

      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.uri.toString(), 'https://api.test/api/v1/auth/password-reset/confirm');
      expect(sentBody(), {'resetToken': 'fake-reset-token', 'newPassword': 'fake-new-password'});
    });

    test('verifies the code with POST /auth/password-reset/verify and reads the grant', () async {
      answer = (_) => jsonBody(200, {'resetToken': 'fake-reset-token', 'expiresIn': 600});

      final grant = await repository.verifyPasswordResetCode(verify);

      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.uri.toString(), 'https://api.test/api/v1/auth/password-reset/verify');
      expect(sentBody(), {'email': 'ana@example.com', 'code': '042917'});
      expect(grant.token, 'fake-reset-token');
      expect(grant.expiresIn, 600);
    });

    test('400 invalid-code on verify is a typed failure; 429 propagates', () async {
      answer = (_) => problemBody(400, 'invalid-code');
      await expectLater(
        repository.verifyPasswordResetCode(verify),
        throwsA(isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.invalidCode)),
      );

      answer = (_) => problemBody(429, 'too-many-requests');
      await expectLater(
        repository.verifyPasswordResetCode(verify),
        throwsA(isA<ProblemFailure>().having((f) => f.status, 'status', 429)),
      );
    });

    test('a verify answer without the token is a ProblemFailure', () async {
      answer = (_) => jsonBody(200, {'expiresIn': 600});

      await expectLater(
        repository.verifyPasswordResetCode(verify),
        throwsA(isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.unknown)),
      );
    });

    test('400 invalid-reset-token on confirm is a typed failure', () async {
      answer = (_) => problemBody(400, 'invalid-reset-token');

      await expectLater(
        repository.confirmPasswordReset(confirm),
        throwsA(
          isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.invalidResetToken),
        ),
      );
    });

    test('400 validation-error and 429 propagate', () async {
      answer = (_) => validationProblemBody(['newPassword']);
      await expectLater(repository.confirmPasswordReset(confirm), throwsA(isA<ProblemFailure>()));

      answer = (_) => problemBody(429, 'too-many-requests');
      await expectLater(repository.confirmPasswordReset(confirm), throwsA(isA<ProblemFailure>()));
    });
  });
}

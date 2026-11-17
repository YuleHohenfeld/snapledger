import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/api/api_stack.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/email_verification_repository.dart';

import '../../../../../support/fake_http_adapter.dart';
import '../../../../../support/json_fixtures.dart';

void main() {
  late FakeHttpAdapter adapter;
  late ResponseBody Function() answer;
  late ApiEmailVerificationRepository repository;

  setUp(() {
    answer = () => textBody(202, '');
    adapter = FakeHttpAdapter((_) async => answer());
    final config = AppConfig.parse('https://api.test', isRelease: true);
    repository = ApiEmailVerificationRepository(
      ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = adapter),
    );
  });

  group('sendCode', () {
    test('POSTs /users/me/email-verification with no body and accepts 202', () async {
      await repository.sendCode();

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.toString(), 'https://api.test/api/v1/users/me/email-verification');
      expect(request.data, isNull);
    });

    test('a 429 is a typed too-many-requests failure', () async {
      answer = () => problemBody(429, 'too-many-requests');

      await expectLater(
        repository.sendCode(),
        throwsA(
          isA<ProblemFailure>()
              .having((f) => f.status, 'status', 429)
              .having((f) => f.type, 'type', ProblemType.tooManyRequests),
        ),
      );
    });

    test('a 401 is a typed unauthorized failure', () async {
      answer = () => problemBody(401, 'unauthorized');

      await expectLater(
        repository.sendCode(),
        throwsA(isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.unauthorized)),
      );
    });
  });

  group('confirm', () {
    test('POSTs the code to /users/me/email-verification/confirm and parses the user', () async {
      answer = () => jsonBody(200, fakeUserJson(emailVerified: true));

      final user = await repository.confirm('042917');

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(
        request.uri.toString(),
        'https://api.test/api/v1/users/me/email-verification/confirm',
      );
      expect(request.data, {'code': '042917'});
      expect(user.emailVerified, isTrue);
    });

    test('400 invalid-code is a typed failure', () async {
      answer = () => problemBody(400, 'invalid-code');

      await expectLater(
        repository.confirm('000000'),
        throwsA(isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.invalidCode)),
      );
    });

    test('a 2xx body that breaks the contract becomes a ProblemFailure', () async {
      answer = () => jsonBody(200, {'id': 'x'});

      await expectLater(repository.confirm('042917'), throwsA(isA<ProblemFailure>()));
    });
  });
}

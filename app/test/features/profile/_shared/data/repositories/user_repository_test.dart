import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/api/api_stack.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';

import '../../../../../support/fake_http_adapter.dart';
import '../../../../../support/json_fixtures.dart';

void main() {
  late FakeHttpAdapter adapter;
  late ResponseBody Function() answer;
  late ApiUserRepository repository;

  setUp(() {
    answer = () => jsonBody(200, fakeUserJson());
    adapter = FakeHttpAdapter((_) async => answer());
    final config = AppConfig.parse('https://api.test', isRelease: true);
    repository = ApiUserRepository(
      ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = adapter),
    );
  });

  test('GETs /users/me and parses the user', () async {
    final user = await repository.fetchCurrent();

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.toString(), 'https://api.test/api/v1/users/me');
    expect(user.name, 'Ana Souza');
    expect(user.currency, 'BRL');
  });

  test('a 401 becomes a typed ProblemFailure', () async {
    answer = () => problemBody(401, 'unauthorized');

    await expectLater(
      repository.fetchCurrent(),
      throwsA(isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.unauthorized)),
    );
  });

  test('a 2xx body that breaks the contract becomes a ProblemFailure', () async {
    answer = () => jsonBody(200, {'id': 'x'});

    await expectLater(repository.fetchCurrent(), throwsA(isA<ProblemFailure>()));
  });
}

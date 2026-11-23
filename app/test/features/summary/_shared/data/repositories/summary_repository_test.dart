import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/api/api_stack.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/summary/_shared/data/repositories/summary_repository.dart';

import '../../../../../support/fake_http_adapter.dart';
import '../../../../../support/json_fixtures.dart';

void main() {
  late FakeHttpAdapter adapter;
  late ResponseBody Function() answer;
  late ApiSummaryRepository repository;

  Map<String, Object?> body({Object? total = '1234.56'}) => {
    'month': '2026-11',
    'currency': 'BRL',
    'total': total,
    'expenseCount': 37,
    'previousMonthTotal': '980.00',
    'byCategory': [
      {
        'categoryId': '0b8a3f52-1111-4222-8333-444455556666',
        'categoryName': 'Groceries',
        'total': '612.30',
        'expenseCount': 9,
        'percentage': '49.60',
      },
    ],
  };

  setUp(() {
    answer = () => jsonBody(200, body());
    adapter = FakeHttpAdapter((_) async => answer());
    final config = AppConfig.parse('https://api.test', isRelease: true);
    repository = ApiSummaryRepository(
      ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = adapter),
    );
  });

  test('GETs /expenses/summary with month=YYYY-MM and parses the answer', () async {
    final summary = await repository.fetch(const Month(2026, 3));

    final sent = adapter.requests.single;
    expect(sent.method, 'GET');
    expect(sent.uri.path, '/api/v1/expenses/summary');
    expect(sent.uri.queryParameters, {'month': '2026-03'});
    expect(summary.total.toStringAsFixed(2), '1234.56');
    expect(summary.byCategory.single.categoryName, 'Groceries');
  });

  test('a 400 is a typed ProblemFailure', () async {
    answer = () => validationProblemBody(['month']);

    await expectLater(
      repository.fetch(const Month(2026, 11)),
      throwsA(isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.validationError)),
    );
  });

  test('a 2xx body that breaks the contract becomes a ProblemFailure', () async {
    answer = () => jsonBody(200, body(total: 'abc'));

    await expectLater(repository.fetch(const Month(2026, 11)), throwsA(isA<ProblemFailure>()));
  });

  test('a network failure is a typed NetworkFailure', () async {
    final offline = FakeHttpAdapter((options) async => throw DioException(requestOptions: options));
    final config = AppConfig.parse('https://api.test', isRelease: true);
    final broken = ApiSummaryRepository(
      ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = offline),
    );

    await expectLater(broken.fetch(const Month(2026, 11)), throwsA(isA<NetworkFailure>()));
  });
}

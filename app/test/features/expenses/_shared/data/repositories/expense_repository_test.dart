import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/api/api_stack.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_request.dart';
import 'package:snapledger/features/expenses/_shared/data/repositories/expense_repository.dart';

import '../../../../../support/fake_http_adapter.dart';
import '../../../../../support/json_fixtures.dart';

void main() {
  const expenseId = 'c3d4e5f6-a7b8-4c9d-8e0f-1a2b3c4d5e6f';

  late FakeHttpAdapter adapter;
  late ResponseBody Function() answer;
  late ApiExpenseRepository repository;
  late int changes;

  Map<String, Object?> expenseJson({String amount = '42.90'}) => {
    'id': expenseId,
    'amount': amount,
    'description': 'Weekly groceries',
    'date': '2026-11-08',
    'category': fakeCategoryJson(id: fakeDefaultCategoryId, name: 'Groceries', key: 'groceries'),
    'createdAt': '2026-11-08T21:15:00Z',
    'updatedAt': '2026-11-08T21:15:00Z',
  };

  final request = ExpenseRequest(
    amount: Decimal.parse('42.9'),
    description: 'Weekly groceries',
    date: DateTime(2026, 11, 8),
    categoryId: fakeDefaultCategoryId,
  );

  setUp(() {
    answer = () => jsonBody(200, <Object?>[]);
    adapter = FakeHttpAdapter((_) async => answer());
    final config = AppConfig.parse('https://api.test', isRelease: true);
    repository = ApiExpenseRepository(
      ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = adapter),
    );
    changes = 0;
    repository.changes.addListener(() => changes++);
  });

  tearDown(() => repository.dispose());

  group('listMonth', () {
    test(
      'GETs /expenses with month=YYYY-MM only, and parses the list in the server order',
      () async {
        answer = () => jsonBody(200, [expenseJson(), expenseJson(amount: '10.00')]);

        final expenses = await repository.listMonth(const Month(2026, 11));

        final sent = adapter.requests.single;
        expect(sent.method, 'GET');
        expect(sent.uri.path, '/api/v1/expenses');
        expect(sent.uri.queryParameters, {'month': '2026-11'});
        expect(expenses.map((e) => e.amount.toStringAsFixed(2)), ['42.90', '10.00']);
      },
    );

    test('adds categoryId only when it is given', () async {
      await repository.listMonth(const Month(2026, 3), categoryId: fakeCategoryId);

      expect(adapter.requests.single.uri.queryParameters, {
        'month': '2026-03',
        'categoryId': fakeCategoryId,
      });
    });

    test('an element that breaks the contract becomes a ProblemFailure', () async {
      answer = () => jsonBody(200, [
        {'id': 'x'},
      ]);

      await expectLater(
        repository.listMonth(const Month(2026, 11)),
        throwsA(isA<ProblemFailure>()),
      );
    });

    test('a read never fires changes', () async {
      await repository.listMonth(const Month(2026, 11));

      expect(changes, 0);
    });
  });

  group('get', () {
    test('GETs /expenses/{id} with the id encoded as one path segment', () async {
      answer = () => jsonBody(200, expenseJson());

      final expense = await repository.get(expenseId);

      expect(adapter.requests.single.uri.path, '/api/v1/expenses/$expenseId');
      expect(expense.id, expenseId);
      await repository.get('a/b');
      expect(adapter.requests.last.uri.toString(), 'https://api.test/api/v1/expenses/a%2Fb');
    });

    test('404 not-found becomes a typed ProblemFailure', () async {
      answer = () => problemBody(404, 'not-found');

      await expectLater(
        repository.get(expenseId),
        throwsA(isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.notFound)),
      );
    });
  });

  group('writes', () {
    test('create POSTs the body (amount as a 2-place string) and fires changes once', () async {
      answer = () => jsonBody(201, expenseJson());

      final created = await repository.create(request);

      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.uri.path, '/api/v1/expenses');
      expect(sent.data, {
        'amount': '42.90',
        'description': 'Weekly groceries',
        'date': '2026-11-08',
        'categoryId': fakeDefaultCategoryId,
      });
      expect(created.id, expenseId);
      expect(changes, 1);
    });

    test('update PUTs the whole body to /expenses/{id} and fires changes', () async {
      answer = () => jsonBody(200, expenseJson());

      await repository.update(expenseId, request);

      final sent = adapter.requests.single;
      expect(sent.method, 'PUT');
      expect(sent.uri.path, '/api/v1/expenses/$expenseId');
      expect((sent.data as Map).keys, ['amount', 'description', 'date', 'categoryId']);
      expect(changes, 1);
    });

    test('delete DELETEs /expenses/{id} and fires changes', () async {
      answer = () => textBody(204, '');

      await repository.delete(expenseId);

      final sent = adapter.requests.single;
      expect(sent.method, 'DELETE');
      expect(sent.uri.path, '/api/v1/expenses/$expenseId');
      expect(changes, 1);
    });

    test('a failed write fires nothing and is a typed failure', () async {
      answer = () => validationProblemBody(['amount']);

      await expectLater(
        repository.create(request),
        throwsA(isA<ProblemFailure>().having((f) => f.fieldErrors, 'fields', ['amount'])),
      );
      answer = () => validationProblemBody(['amount']);
      await expectLater(repository.update(expenseId, request), throwsA(isA<ProblemFailure>()));
      answer = () => problemBody(500, 'internal-error');
      await expectLater(repository.delete(expenseId), throwsA(isA<ProblemFailure>()));

      expect(changes, 0);
    });

    test(
      'an update answered 404 does not fire changes: it may be the category that is gone',
      () async {
        answer = () => problemBody(404, 'not-found');

        await expectLater(
          repository.update(expenseId, request),
          throwsA(isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.notFound)),
        );

        expect(changes, 0);
      },
    );

    test('a delete answered 404 fires changes: the expense is gone, lists must reload', () async {
      answer = () => problemBody(404, 'not-found');

      await expectLater(
        repository.delete(expenseId),
        throwsA(isA<ProblemFailure>().having((f) => f.type, 'type', ProblemType.notFound)),
      );

      expect(changes, 1);
    });

    test('notifyChanged fires changes', () {
      repository.notifyChanged();

      expect(changes, 1);
    });

    test('an answer that arrives after dispose does not notify', () async {
      final gate = Completer<void>();
      final slow = FakeHttpAdapter((_) async {
        await gate.future;
        return textBody(204, '');
      });
      final config = AppConfig.parse('https://api.test', isRelease: true);
      final closing = ApiExpenseRepository(
        ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = slow),
      );
      final pending = closing.delete(expenseId);
      closing.dispose();

      gate.complete();
      await pending;
      // Reaching here without "used after being disposed" is the assertion.
    });

    test('a network failure fires nothing', () async {
      final offline = FakeHttpAdapter(
        (options) async => throw DioException(requestOptions: options),
      );
      final config = AppConfig.parse('https://api.test', isRelease: true);
      final broken = ApiExpenseRepository(
        ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = offline),
      );
      var fired = 0;
      broken.changes.addListener(() => fired++);

      await expectLater(broken.create(request), throwsA(isA<NetworkFailure>()));

      expect(fired, 0);
      broken.dispose();
    });

    test(
      'a created expense the server accepted fires changes even if the answer body is unreadable',
      () async {
        answer = () => jsonBody(201, {'id': 'x'});

        await expectLater(repository.create(request), throwsA(isA<ProblemFailure>()));

        expect(changes, 1);
      },
    );
  });
}

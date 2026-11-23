import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_model.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_request.dart';

import '../../../../../support/json_fixtures.dart';

void main() {
  Map<String, Object?> json({
    Object? id = 'c3d4e5f6-a7b8-4c9d-8e0f-1a2b3c4d5e6f',
    Object? amount = '42.90',
    Object? description = 'Weekly groceries',
    Object? date = '2026-11-08',
    Object? category,
  }) => {
    'id': id,
    'amount': amount,
    'description': description,
    'date': date,
    'category': category ?? fakeCategoryJson(id: fakeDefaultCategoryId, name: 'Groceries', key: 'groceries'),
    'createdAt': '2026-11-08T21:15:00Z',
    'updatedAt': '2026-11-08T21:16:00Z',
  };

  group('ExpenseModel.fromJson', () {
    test('reads the contract: exact amount, calendar day, category and timestamps', () {
      final expense = ExpenseModel.fromJson(json());

      expect(expense.amount, Decimal.parse('42.90'));
      expect(expense.date, DateTime(2026, 11, 8));
      expect(expense.description, 'Weekly groceries');
      expect(expense.category.key, 'groceries');
      expect(expense.createdAt, DateTime.utc(2026, 11, 8, 21, 15));
      expect(expense.updatedAt, DateTime.utc(2026, 11, 8, 21, 16));
    });

    test('keeps a large amount exact (no double on the way)', () {
      final expense = ExpenseModel.fromJson(json(amount: '9999999999.99'));

      expect(expense.amount.toStringAsFixed(2), '9999999999.99');
    });

    for (final (label, bad) in <(String, Map<String, Object?>)>[
      ('a missing id', json(id: null)),
      ('an id that is not a UUID', json(id: '../expenses')),
      ('a numeric amount', json(amount: 42.9)),
      ('an amount with 3 places', json(amount: '1.234')),
      ('a negative amount', json(amount: '-1.00')),
      ('an amount with an exponent', json(amount: '1e3')),
      ('an empty description', json(description: '')),
      ('a date with a time', json(date: '2026-11-08T10:00:00')),
      ('a day that does not exist', json(date: '2026-02-30')),
      ('a missing category', json(category: 'x')),
    ]) {
      test('throws FormatException for $label', () {
        expect(() => ExpenseModel.fromJson(bad), throwsFormatException);
      });
    }

    test('an error message never carries the bad value', () {
      expect(
        () => ExpenseModel.fromJson(json(amount: 'secret-12')),
        throwsA(isA<FormatException>().having((e) => e.toString(), 'text', isNot(contains('secret')))),
      );
    });

    test('toString hides amount and description', () {
      final text = ExpenseModel.fromJson(json()).toString();

      expect(text, isNot(contains('42.90')));
      expect(text, isNot(contains('groceries')));
    });

    test('has value equality', () {
      expect(ExpenseModel.fromJson(json()), ExpenseModel.fromJson(json()));
      expect(ExpenseModel.fromJson(json()).hashCode, ExpenseModel.fromJson(json()).hashCode);
      expect(ExpenseModel.fromJson(json()), isNot(ExpenseModel.fromJson(json(amount: '42.91'))));
    });
  });

  group('ExpenseRequest', () {
    test('toJson sends the amount as a string with 2 places and the date as yyyy-MM-dd', () {
      final request = ExpenseRequest(
        amount: Decimal.parse('42.9'),
        description: 'Weekly groceries',
        date: DateTime(2026, 3, 8, 22),
        categoryId: fakeDefaultCategoryId,
      );

      expect(request.toJson(), {
        'amount': '42.90',
        'description': 'Weekly groceries',
        'date': '2026-03-08',
        'categoryId': fakeDefaultCategoryId,
      });
    });

    test('a whole amount keeps the 2 places', () {
      final request = ExpenseRequest(
        amount: Decimal.parse('1500'),
        description: 'Rent',
        date: DateTime(2026, 11),
        categoryId: fakeDefaultCategoryId,
      );

      expect(request.toJson()['amount'], '1500.00');
    });

    test('toString hides amount and description', () {
      final request = ExpenseRequest(
        amount: Decimal.parse('42.90'),
        description: 'Weekly groceries',
        date: DateTime(2026, 11),
        categoryId: fakeDefaultCategoryId,
      );

      expect(request.toString(), isNot(contains('42.90')));
      expect(request.toString(), isNot(contains('groceries')));
    });
  });
}

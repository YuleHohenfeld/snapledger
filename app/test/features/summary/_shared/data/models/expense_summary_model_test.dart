import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/summary/_shared/data/models/expense_summary_model.dart';

void main() {
  const categoryId = '0b8a3f52-1111-4222-8333-444455556666';

  Map<String, Object?> row({
    Object? id = categoryId,
    Object? name = 'Groceries',
    Object? total = '612.30',
    Object? count = 9,
    Object? percentage = '49.60',
  }) => {
    'categoryId': id,
    'categoryName': name,
    'total': total,
    'expenseCount': count,
    'percentage': percentage,
  };

  Map<String, Object?> json({
    Object? month = '2026-11',
    Object? currency = 'BRL',
    Object? total = '1234.56',
    Object? count = 37,
    Object? previous = '980.00',
    Object? byCategory,
  }) => {
    'month': month,
    'currency': currency,
    'total': total,
    'expenseCount': count,
    'previousMonthTotal': previous,
    'byCategory': byCategory ?? [row()],
  };

  group('ExpenseSummaryModel.fromJson', () {
    test('reads the contract: exact money, the month and the ranked categories', () {
      final summary = ExpenseSummaryModel.fromJson(json());

      expect(summary.month, const Month(2026, 11));
      expect(summary.currency, 'BRL');
      expect(summary.total, Decimal.parse('1234.56'));
      expect(summary.expenseCount, 37);
      expect(summary.previousMonthTotal, Decimal.parse('980.00'));
      final first = summary.byCategory.single;
      expect(first.categoryId, categoryId);
      expect(first.categoryName, 'Groceries');
      expect(first.total, Decimal.parse('612.30'));
      expect(first.expenseCount, 9);
      expect(first.percentage, Decimal.parse('49.60'));
    });

    test('an empty month is valid', () {
      final summary = ExpenseSummaryModel.fromJson(
        json(total: '0.00', count: 0, previous: '0.00', byCategory: <Object?>[]),
      );

      expect(summary.expenseCount, 0);
      expect(summary.byCategory, isEmpty);
    });

    test('keeps a huge total exact (no double on the way)', () {
      final summary = ExpenseSummaryModel.fromJson(json(total: '99999999999999.99'));

      expect(summary.total.toStringAsFixed(2), '99999999999999.99');
    });

    test('the category list cannot be changed after reading', () {
      final summary = ExpenseSummaryModel.fromJson(json());

      expect(summary.byCategory.clear, throwsUnsupportedError);
    });

    for (final (field, value) in <(String, Object?)>[
      ('month', '2026-13'),
      ('month', '2026-1'),
      ('month', null),
      ('currency', ''),
      ('currency', 5),
      ('total', 12.5),
      ('total', '-1.00'),
      ('total', '1e3'),
      ('total', '12.345'),
      ('expenseCount', -1),
      ('expenseCount', '3'),
      ('previousMonthTotal', null),
      ('byCategory', 'x'),
      ('byCategory', null),
    ]) {
      test('rejects $field = $value', () {
        final body = json()..[field] = value;

        expect(() => ExpenseSummaryModel.fromJson(body), throwsFormatException);
      });
    }

    test('rejects a row that is not an object', () {
      expect(() => ExpenseSummaryModel.fromJson(json(byCategory: ['x'])), throwsFormatException);
    });

    test('an error message names the field and never the value', () {
      expect(
        () => ExpenseSummaryModel.fromJson(json(total: 'secret-1')),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('total'))
              .having((e) => e.message, 'message', isNot(contains('secret'))),
        ),
      );
    });
  });

  group('CategorySummaryModel.fromJson', () {
    test('accepts the bounds of a percentage', () {
      expect(CategorySummaryModel.fromJson(row(percentage: '0.00')).percentage, Decimal.zero);
      expect(
        CategorySummaryModel.fromJson(row(percentage: '100.00')).percentage,
        Decimal.fromInt(100),
      );
    });

    for (final (field, value) in <(String, Object?)>[
      ('categoryId', 'not-a-uuid'),
      ('categoryId', ''),
      ('categoryName', ''),
      ('total', 'abc'),
      ('expenseCount', 1.5),
      ('percentage', '100.01'),
      ('percentage', '-1.00'),
      ('percentage', 49.6),
      ('percentage', '5e1'),
    ]) {
      test('rejects $field = $value', () {
        final body = row()..[field] = value;

        expect(() => CategorySummaryModel.fromJson(body), throwsFormatException);
      });
    }

    test('toString shows no name and no amount', () {
      final text = CategorySummaryModel.fromJson(row()).toString();

      expect(text, contains(categoryId));
      expect(text, isNot(contains('Groceries')));
      expect(text, isNot(contains('612')));
    });
  });

  test('two summaries read from the same JSON are equal', () {
    expect(ExpenseSummaryModel.fromJson(json()), ExpenseSummaryModel.fromJson(json()));
    expect(
      ExpenseSummaryModel.fromJson(json()).hashCode,
      ExpenseSummaryModel.fromJson(json()).hashCode,
    );
    expect(
      ExpenseSummaryModel.fromJson(json()),
      isNot(ExpenseSummaryModel.fromJson(json(total: '1.00'))),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/time/month.dart';

void main() {
  test('previous and next cross the year boundary', () {
    expect(const Month(2026, 1).previous, const Month(2025, 12));
    expect(const Month(2025, 12).next, const Month(2026, 1));
    expect(const Month(2026, 6).previous, const Month(2026, 5));
    expect(const Month(2026, 6).next, const Month(2026, 7));
  });

  test('toQuery is YYYY-MM, zero padded', () {
    expect(const Month(2026, 3).toQuery(), '2026-03');
    expect(const Month(2026, 11).toQuery(), '2026-11');
    expect(const Month(999, 1).toQuery(), '0999-01');
  });

  test('of reads the year and month of the date, ignoring the time', () {
    expect(Month.of(DateTime(2026, 11, 30, 23, 59)), const Month(2026, 11));
    expect(Month.of(DateTime(2026, 12, 1)), const Month(2026, 12));
  });

  test('contains compares the date as written, first and last day included', () {
    const month = Month(2026, 2);
    expect(month.contains(DateTime(2026, 2)), isTrue);
    expect(month.contains(DateTime(2026, 2, 28, 23, 59)), isTrue);
    expect(month.contains(DateTime(2026, 3)), isFalse);
    expect(month.contains(DateTime(2025, 2, 10)), isFalse);
  });

  test('has value equality and an order', () {
    expect(const Month(2026, 4), const Month(2026, 4));
    expect(const Month(2026, 4).hashCode, const Month(2026, 4).hashCode);
    expect(const Month(2026, 4) < const Month(2026, 5), isTrue);
    expect(const Month(2027, 1) > const Month(2026, 12), isTrue);
    expect(const Month(2026, 4).firstDay, DateTime(2026, 4));
  });
}

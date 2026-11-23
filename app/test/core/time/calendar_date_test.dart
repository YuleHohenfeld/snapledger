import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/time/calendar_date.dart';

void main() {
  test('formatCalendarDate writes the date as yyyy-MM-dd, zero padded, ignoring the time', () {
    expect(formatCalendarDate(DateTime(2026, 3, 8, 23, 59)), '2026-03-08');
    expect(formatCalendarDate(DateTime(2000)), '2000-01-01');
  });

  test('parseCalendarDate reads a real day as local midnight', () {
    expect(parseCalendarDate('2026-11-08'), DateTime(2026, 11, 8));
    expect(parseCalendarDate('2024-02-29'), DateTime(2024, 2, 29));
  });

  for (final text in ['2026-02-30', '2026-13-01', '2025-02-29', '2026-1-1', '', '2026-11-08T10:00:00', ' 2026-11-08']) {
    test('parseCalendarDate refuses "$text"', () => expect(parseCalendarDate(text), isNull));
  }

  test('calendarDay cuts the time off', () {
    expect(calendarDay(DateTime(2026, 11, 8, 17, 30, 5)), DateTime(2026, 11, 8));
  });
}

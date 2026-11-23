import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:snapledger/core/l10n/date_format.dart';
import 'package:snapledger/core/time/month.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('pt_BR');
  });

  test('the month label follows the locale', () {
    expect(formatMonthLabel(const Month(2026, 11), locale: 'en'), 'November 2026');
    expect(formatMonthLabel(const Month(2026, 11), locale: 'pt_BR'), 'novembro de 2026');
  });

  test('a day header is the weekday and the date in the locale', () {
    expect(formatDayHeader(DateTime(2026, 11, 8), locale: 'en'), 'Sun, Nov 8');
    expect(formatDayHeader(DateTime(2026, 11, 8), locale: 'pt_BR'), 'dom., 8 de nov.');
  });

  test('a date is written in full in the locale', () {
    expect(formatDate(DateTime(2026, 11, 8), locale: 'en'), 'Nov 8, 2026');
    expect(formatDate(DateTime(2026, 11, 8), locale: 'pt_BR'), '8 de nov. de 2026');
  });
}

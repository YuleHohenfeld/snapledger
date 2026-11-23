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
}

/// [date] with the time cut off: local midnight of the same calendar day.
/// PT: [date] sem a hora: meia-noite local do mesmo dia do calendário.
/// Notes: docs/code-notes/app-core.md#calendar-dates
DateTime calendarDay(DateTime date) => DateTime(date.year, date.month, date.day);

/// The contract's date text for [date]: `2026-03-08` (its own year, month and day, no conversion).
/// PT: O texto de data do contrato para [date]: `2026-03-08` (o próprio ano, mês e dia, sem conversão).
/// Notes: docs/code-notes/app-core.md#calendar-dates
String formatCalendarDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

final _calendarDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Reads `yyyy-MM-dd` as local midnight of that day, or null when it is not a real calendar day.
/// PT: Lê `yyyy-MM-dd` como meia-noite local desse dia, ou null quando não é um dia real do calendário.
/// Notes: docs/code-notes/app-core.md#calendar-dates
DateTime? parseCalendarDate(String text) {
  final match = _calendarDate.firstMatch(text);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  // `2026-02-31` would roll over to March: a day that does not exist is refused, not moved.
  // PT: `2026-02-31` viraria março: um dia que não existe é recusado, não deslocado.
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

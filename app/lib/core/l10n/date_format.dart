import 'package:intl/intl.dart';
import 'package:snapledger/core/time/month.dart';

/// The month as a title in [locale] (`November 2026`); the locale's date data comes from the app's delegates.
/// PT: O mês como título no [locale] (`November 2026`); os dados de data do locale vêm dos delegates do app.
/// Notes: docs/code-notes/app-core.md#month
String formatMonthLabel(Month month, {required String locale}) =>
    DateFormat.yMMMM(locale).format(month.firstDay);

/// A day as a list header in [locale]: weekday and date (`Sun, Nov 8`).
/// PT: Um dia como cabeçalho de lista no [locale]: dia da semana e data (`Sun, Nov 8`).
/// Notes: docs/code-notes/app-core.md#calendar-dates
String formatDayHeader(DateTime date, {required String locale}) =>
    DateFormat.MMMEd(locale).format(date);

/// A calendar day in [locale] (`Nov 8, 2026`), for a date field.
/// PT: Um dia do calendário no [locale] (`Nov 8, 2026`), para um campo de data.
/// Notes: docs/code-notes/app-core.md#calendar-dates
String formatDate(DateTime date, {required String locale}) => DateFormat.yMMMd(locale).format(date);

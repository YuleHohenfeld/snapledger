import 'package:intl/intl.dart';
import 'package:snapledger/core/time/month.dart';

/// The month as a title in [locale] (`November 2026`); the locale's date data comes from the app's delegates.
/// PT: O mês como título no [locale] (`November 2026`); os dados de data do locale vêm dos delegates do app.
/// Notes: docs/code-notes/app-core.md#month
String formatMonthLabel(Month month, {required String locale}) =>
    DateFormat.yMMMM(locale).format(month.firstDay);

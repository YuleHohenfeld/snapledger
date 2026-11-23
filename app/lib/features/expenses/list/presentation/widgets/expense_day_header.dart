import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/l10n/date_format.dart';
import 'package:snapledger/core/l10n/money_format.dart';
import 'package:snapledger/features/expenses/list/application/viewmodel/expense_list_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// A day's header: "Today", "Yesterday" or weekday and date, with the sum of that day.
/// PT: O cabeçalho de um dia: "Hoje", "Ontem" ou dia da semana e data, com a soma desse dia.
/// Notes: docs/code-notes/app-expenses.md#expenselistpage
class ExpenseDayHeader extends StatelessWidget {
  const ExpenseDayHeader({required this.group, required this.currency, super.key});

  final ExpenseDayGroup group;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final style = Theme.of(context).textTheme.titleSmall;
    final label = switch (group.kind) {
      ExpenseDayKind.today => l10n.expenseListToday,
      ExpenseDayKind.yesterday => l10n.expenseListYesterday,
      ExpenseDayKind.other => formatDayHeader(group.date, locale: locale),
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.m, bottom: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: style),
            Text(formatMoney(group.total, currency: currency, locale: locale), style: style),
          ],
        ),
      ),
    );
  }
}

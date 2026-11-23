import 'dart:async';

import 'package:flutter/material.dart';
import 'package:snapledger/core/l10n/date_format.dart';
import 'package:snapledger/features/expenses/_shared/presentation/expense_text.dart';
import 'package:snapledger/features/expenses/form/application/controller/expense_form_controller.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The date field: shows the chosen day and opens the system date picker; the result goes to the Controller.
/// PT: O campo de data: mostra o dia escolhido e abre o seletor de data do sistema; o resultado vai ao Controller.
/// Notes: docs/code-notes/app-expenses.md#expenseformpage
class ExpenseDateField extends StatelessWidget {
  const ExpenseDateField({required this.controller, this.serverError, super.key});

  final ExpenseFormController controller;

  /// The text for a server `date` error, or null.
  /// PT: O texto de um erro de `date` do servidor, ou null.
  final String? serverError;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.pickerStart,
      firstDate: controller.firstDate,
      lastDate: controller.lastDate,
      helpText: AppLocalizations.of(context).expenseFormDateLabel,
    );
    controller.onDatePicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    return ListenableBuilder(
      listenable: Listenable.merge([controller.date, controller.dateError]),
      builder: (context, _) {
        final date = controller.date.value;
        return Semantics(
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => unawaited(_pick(context)),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.expenseFormDateLabel,
                suffixIcon: const Icon(Icons.calendar_today_outlined),
                errorText: expenseDateErrorText(l10n, controller.dateError.value) ?? serverError,
              ),
              child: Text(date == null ? '' : formatDate(date, locale: locale)),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/features/expenses/form/application/controller/expense_form_controller.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Under the amount field: the typed amount written in the user's currency ("Will be saved as R$ 42,90"),
/// so a misplaced separator is seen before saving.
/// PT: Sob o campo de valor: o valor digitado escrito na moeda do usuário ("Será salvo como R$ 42,90"),
/// para um separador fora do lugar ser visto antes de salvar.
/// Notes: docs/code-notes/app-expenses.md#expenseformpage
class AmountPreview extends StatelessWidget {
  const AmountPreview({required this.controller, super.key});

  final ExpenseFormController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    return ListenableBuilder(
      listenable: controller.amountField,
      builder: (context, _) {
        final text = controller.previewText;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs, left: AppSpacing.m),
          child: Semantics(
            liveRegion: true,
            child: Text(text == null ? '' : l10n.expenseFormAmountPreview(text), style: style),
          ),
        );
      },
    );
  }
}

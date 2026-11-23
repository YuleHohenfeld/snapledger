import 'package:flutter/material.dart';
import 'package:snapledger/core/design/widgets/empty_state.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The expense to edit is gone (deleted elsewhere, or a link with a bad id): says so and offers "Back".
/// PT: O gasto a editar sumiu (apagado em outro lugar, ou um link com id ruim): avisa e oferece "Voltar".
/// Notes: docs/code-notes/app-expenses.md#expenseformpage
class ExpenseNotFound extends StatelessWidget {
  const ExpenseNotFound({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.search_off,
      title: l10n.expenseFormNotFoundTitle,
      body: l10n.expenseFormNotFoundBody,
      action: OutlinedButton(onPressed: onBack, child: Text(l10n.expenseFormBack)),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The page header of wide windows: the "Expenses" title and a compact "New expense" button.
/// PT: O cabeçalho da página em janelas largas: o título "Despesas" e um botão compacto "New expense".
/// Notes: docs/code-notes/app-expenses.md#expenselistpage
class ExpenseListHeader extends StatelessWidget {
  const ExpenseListHeader({required this.onNewTapped, super.key});

  final VoidCallback onNewTapped;

  static const _topPadding = AppSpacing.l;
  static const _horizontalPadding = AppSpacing.m;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_horizontalPadding, _topPadding, _horizontalPadding, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(l10n.expensesTitle, style: Theme.of(context).textTheme.headlineMedium),
            ),
          ),
          FilledButton.icon(
            onPressed: onNewTapped,
            icon: const Icon(Icons.add),
            label: Text(l10n.expenseListNew),
          ),
        ],
      ),
    );
  }
}

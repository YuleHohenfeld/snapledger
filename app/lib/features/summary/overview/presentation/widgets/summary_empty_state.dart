import 'package:flutter/material.dart';
import 'package:snapledger/core/design/widgets/empty_state.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// A month with no expense: says so and offers to add the first one.
/// PT: Um mês sem gasto: diz isso e oferece adicionar o primeiro.
/// Notes: docs/code-notes/app-summary.md#summarypage
class SummaryEmptyState extends StatelessWidget {
  const SummaryEmptyState({required this.onAdd, super.key});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.pie_chart_outline,
      title: l10n.summaryEmptyTitle,
      body: l10n.summaryEmptyBody,
      action: FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: Text(l10n.summaryEmptyAdd),
      ),
    );
  }
}

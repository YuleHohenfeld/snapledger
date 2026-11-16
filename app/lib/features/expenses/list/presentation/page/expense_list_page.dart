import 'package:flutter/material.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Placeholder of the Expenses tab until its feature is built.
/// PT: Marcador da aba Despesas até a feature ser construída.
class ExpenseListPage extends StatelessWidget {
  const ExpenseListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.expensesTitle)),
      body: Center(child: Text(l10n.placeholderComingSoon)),
    );
  }
}

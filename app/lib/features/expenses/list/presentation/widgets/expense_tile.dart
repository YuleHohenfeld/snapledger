import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_colors.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/glass_panel.dart';
import 'package:snapledger/core/design/widgets/pill_chip.dart';
import 'package:snapledger/core/l10n/money_format.dart';
import 'package:snapledger/features/categories/_shared/presentation/category_text.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// One expense row: description, its category as a pill and the amount; a tap opens the edit form.
/// PT: Uma linha de gasto: descrição, a categoria como pílula e o valor; um toque abre o formulário de edição.
/// Notes: docs/code-notes/app-expenses.md#expenselistpage
class ExpenseTile extends StatelessWidget {
  const ExpenseTile({
    required this.expense,
    required this.currency,
    required this.onTap,
    super.key,
  });

  final ExpenseModel expense;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: GlassPanel(
        radius: AppGlass.rowRadius,
        child: ListTile(
          onTap: onTap,
          title: Text(expense.description, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: PillChip(
                label: categoryDisplayName(l10n, expense.category),
                onGradient: false,
              ),
            ),
          ),
          trailing: Text(
            formatMoney(expense.amount, currency: currency, locale: locale),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}

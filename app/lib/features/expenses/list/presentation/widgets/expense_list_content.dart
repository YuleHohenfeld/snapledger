import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/empty_state.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_model.dart';
import 'package:snapledger/features/expenses/list/application/viewmodel/expense_list_view_model.dart';
import 'package:snapledger/features/expenses/list/presentation/widgets/expense_day_header.dart';
import 'package:snapledger/features/expenses/list/presentation/widgets/expense_tile.dart';
import 'package:snapledger/features/expenses/list/presentation/widgets/month_total_card.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The loaded month: total, expenses grouped by day, or the empty state; always pull to refresh.
/// PT: O mês carregado: total, gastos agrupados por dia, ou o estado vazio; sempre com puxar para atualizar.
/// Notes: docs/code-notes/app-expenses.md#expenselistpage
class ExpenseListContent extends StatelessWidget {
  const ExpenseListContent({
    required this.state,
    required this.onRefresh,
    required this.onExpenseTap,
    super.key,
  });

  final ExpenseListLoaded state;
  final Future<void> Function() onRefresh;
  final ValueChanged<ExpenseModel> onExpenseTap;

  /// Room under the last row so the floating button does not cover it.
  /// PT: Espaço sob a última linha para o botão flutuante não cobri-la.
  static const _bottomClearance = 88.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = failureMessage(l10n, state.failure);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        // Scrollable even when short, so the pull to refresh works on an empty month too.
        // PT: Rolável mesmo curta, para o puxar para atualizar funcionar também num mês vazio.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (message != null)
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.m),
              sliver: SliverToBoxAdapter(child: FormErrorBanner(message: message)),
            ),
          if (state.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: l10n.expenseListEmptyTitle,
                body: l10n.expenseListEmptyBody,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.m,
                AppSpacing.s,
                AppSpacing.m,
                _bottomClearance,
              ),
              sliver: SliverList.list(
                children: [
                  MonthTotalCard(total: state.monthTotal, currency: state.currency),
                  for (final group in state.days) ...[
                    ExpenseDayHeader(group: group, currency: state.currency),
                    for (final expense in group.expenses)
                      ExpenseTile(
                        key: ValueKey(expense.id),
                        expense: expense,
                        currency: state.currency,
                        onTap: () => onExpenseTap(expense),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

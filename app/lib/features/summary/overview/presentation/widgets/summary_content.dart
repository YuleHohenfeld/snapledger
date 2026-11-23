import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/design/window_size.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/summary/overview/application/viewmodel/summary_view_model.dart';
import 'package:snapledger/features/summary/overview/presentation/widgets/category_breakdown_chart.dart';
import 'package:snapledger/features/summary/overview/presentation/widgets/summary_empty_state.dart';
import 'package:snapledger/features/summary/overview/presentation/widgets/summary_total_card.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The loaded month: total card and ranked bars, or the empty state; always pull to refresh.
/// PT: O mês carregado: card de total e barras ranqueadas, ou o estado vazio; sempre com puxar para atualizar.
/// Notes: docs/code-notes/app-summary.md#summarypage
class SummaryContent extends StatelessWidget {
  const SummaryContent({
    required this.state,
    required this.onRefresh,
    required this.onAdd,
    super.key,
  });

  final SummaryLoaded state;
  final Future<void> Function() onRefresh;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final message = failureMessage(AppLocalizations.of(context), state.failure);
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
            SliverFillRemaining(hasScrollBody: false, child: SummaryEmptyState(onAdd: onAdd))
          else
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.m),
              // Expanded window: the total on the left, the breakdown on the right; otherwise one column.
              // PT: Janela expandida: o total à esquerda, a divisão à direita; senão uma coluna.
              sliver: WindowSize.of(context) == WindowSize.expanded
                  ? SliverToBoxAdapter(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: SummaryTotalCard(state: state)),
                          const SizedBox(width: AppSpacing.l),
                          Expanded(child: CategoryBreakdownChart(summary: state.summary)),
                        ],
                      ),
                    )
                  : SliverList.list(
                      children: [
                        SummaryTotalCard(state: state),
                        const SizedBox(height: AppSpacing.l),
                        CategoryBreakdownChart(summary: state.summary),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

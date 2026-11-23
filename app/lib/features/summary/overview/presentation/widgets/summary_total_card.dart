import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/gradient_card.dart';
import 'package:snapledger/core/design/widgets/pill_chip.dart';
import 'package:snapledger/core/l10n/money_format.dart';
import 'package:snapledger/core/l10n/percent_format.dart';
import 'package:snapledger/features/summary/overview/application/viewmodel/summary_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The month total on the brand gradient, its expense count and how it compares with the previous month.
/// PT: O total do mês sobre o gradiente da marca, a quantidade de gastos e como ele se compara ao mês anterior.
/// Notes: docs/code-notes/app-summary.md#summarypage
class SummaryTotalCard extends StatelessWidget {
  const SummaryTotalCard({required this.state, super.key});

  final SummaryLoaded state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gradients = BrandGradients.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final summary = state.summary;
    final comparison = state.comparison;
    final percent = comparison.percent == null
        ? null
        : percentText(l10n, comparison.percent!, locale: locale);
    final difference = formatMoney(
      comparison.difference,
      currency: summary.currency,
      locale: locale,
    );
    final (pill, line) = switch (comparison.direction) {
      ComparisonDirection.up => (
        percent == null ? l10n.summaryPillUpNoPercent : l10n.summaryPillUp(percent),
        l10n.summaryComparisonUp(difference),
      ),
      ComparisonDirection.down => (
        percent == null ? l10n.summaryPillDownNoPercent : l10n.summaryPillDown(percent),
        l10n.summaryComparisonDown(difference),
      ),
      ComparisonDirection.same => (l10n.summaryPillSame, l10n.summaryComparisonSame),
    };
    final onHero = text.bodyMedium?.copyWith(color: gradients.onHero);
    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.summaryTotalLabel, style: text.labelLarge?.copyWith(color: gradients.onHero)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            formatMoney(summary.total, currency: summary.currency, locale: locale),
            style: text.headlineMedium?.copyWith(
              color: gradients.onHero,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.summaryExpenseCount(summary.expenseCount), style: onHero),
          const SizedBox(height: AppSpacing.m),
          // The pill and the line read as one sentence for a screen reader.
          // PT: A pílula e a linha são lidas como uma só frase por um leitor de tela.
          Semantics(
            container: true,
            label: '$pill. $line',
            excludeSemantics: true,
            child: Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PillChip(label: pill),
                Text(line, style: onHero),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

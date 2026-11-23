import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/glass_panel.dart';
import 'package:snapledger/core/l10n/money_format.dart';
import 'package:snapledger/core/l10n/percent_format.dart';
import 'package:snapledger/features/summary/_shared/data/models/expense_summary_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Ranked horizontal bars, one per category, built from plain widgets (no chart package).
/// PT: Barras horizontais ranqueadas, uma por categoria, feitas de widgets simples (sem pacote de gráfico).
/// Notes: docs/code-notes/app-summary.md#categorybreakdownchart
class CategoryBreakdownChart extends StatelessWidget {
  const CategoryBreakdownChart({required this.summary, super.key});

  final ExpenseSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassPanel(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.summaryByCategoryTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          for (final category in summary.byCategory)
            _CategoryBar(
              key: ValueKey(category.categoryId),
              category: category,
              currency: summary.currency,
            ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.category, required this.currency, super.key});

  final CategorySummaryModel category;
  final String currency;

  static const _barHeight = 10.0;
  static const _grow = Duration(milliseconds: 450);

  /// The API's percentage as a 0..1 width factor: Decimal division, then one conversion for layout only.
  /// A real share never draws thinner than a sliver, so a 0.4% category is still seen.
  /// PT: A porcentagem da API como fator de largura 0..1: divisão Decimal, e uma conversão só para o layout.
  /// PT: Uma fatia real nunca é desenhada mais fina que um fiapo, então uma categoria de 0,4% ainda aparece.
  static double fraction(Decimal percentage) {
    if (percentage <= Decimal.zero) return 0;
    final value = (percentage / Decimal.fromInt(100)).toDouble();
    return value.clamp(0.02, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final amount = formatMoney(category.total, currency: currency, locale: locale);
    final percent = formatPercent(category.percentage, locale: locale);
    final animate = !MediaQuery.disableAnimationsOf(context);
    // One spoken label per row; the visual pieces inside stay silent so nothing is read twice.
    // PT: Um rótulo falado por linha; as peças visuais dentro ficam mudas para nada ser lido duas vezes.
    return Semantics(
      container: true,
      label: l10n.summaryCategoryRowSemantics(category.categoryName, amount, percent),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category.categoryName,
                    style: text.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Text(amount, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(_barHeight),
              child: SizedBox(
                height: _barHeight,
                child: ColoredBox(
                  // The dark track the gradient fill runs on.
                  // PT: A trilha escura sobre a qual o preenchimento em gradiente corre.
                  color: colors.surfaceContainerLowest,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: fraction(category.percentage)),
                    // Reduce motion: the bar is drawn at its final width at once.
                    // PT: Reduzir movimento: a barra é desenhada já na largura final.
                    duration: animate ? _grow : Duration.zero,
                    curve: Curves.easeOutCubic,
                    builder: (context, factor, _) => FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: factor,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: BrandGradients.of(context).accentGradient,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.summaryCategoryMeta(
                category.expenseCount,
                percentText(l10n, category.percentage, locale: locale),
              ),
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

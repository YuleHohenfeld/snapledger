import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/gradient_card.dart';
import 'package:snapledger/core/l10n/money_format.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The sum of the month on the brand gradient (white text on the deep blue passes WCAG AA).
/// PT: A soma do mês sobre o gradiente da marca (texto branco no azul escuro passa no WCAG AA).
/// Notes: docs/code-notes/app-expenses.md#expenselistpage
class MonthTotalCard extends StatelessWidget {
  const MonthTotalCard({required this.total, required this.currency, super.key});

  final Decimal total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gradients = BrandGradients.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.expenseListMonthTotal,
            style: text.labelLarge?.copyWith(color: gradients.onHero),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            formatMoney(total, currency: currency, locale: locale),
            style: text.headlineMedium?.copyWith(
              color: gradients.onHero,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

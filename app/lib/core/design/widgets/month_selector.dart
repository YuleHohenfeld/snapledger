import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/l10n/date_format.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// `‹ November 2026 ›`: shows [month] and asks for the neighbours; "next" is off when [canGoNext] is false.
/// PT: `‹ November 2026 ›`: mostra [month] e pede os vizinhos; "próximo" fica desligado quando [canGoNext] é falso.
/// Notes: docs/code-notes/app-core.md#month
class MonthSelector extends StatelessWidget {
  const MonthSelector({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    super.key,
    this.canGoNext = true,
  });

  final Month month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool canGoNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: l10n.monthSelectorPrevious,
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        // A live region: a screen reader announces the new month after each tap.
        // PT: Uma live region: o leitor de tela anuncia o novo mês após cada toque.
        Semantics(
          liveRegion: true,
          child: Text(
            formatMonthLabel(month, locale: locale),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton(
          tooltip: l10n.monthSelectorNext,
          onPressed: canGoNext ? onNext : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

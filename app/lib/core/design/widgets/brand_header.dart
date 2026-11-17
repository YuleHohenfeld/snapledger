import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/pill_chip.dart';
import 'package:snapledger/core/design/widgets/scan_frame.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The brand block on the gradient: kicker, the name inside a scan frame with an "AI" chip, and the tagline.
/// [compact] keeps only the name and the chip (secondary screens, keyboard open).
/// PT: O bloco de marca sobre o gradiente: rótulo, o nome numa moldura de scan com um chip "AI", e o slogan.
/// [compact] mantém só o nome e o chip (telas secundárias, teclado aberto).
/// Notes: docs/code-notes/app-auth.md#design-widgets
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final onHero = BrandGradients.of(context).onHero;
    final wordmark = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScanFrame(
          child: Text(
            AppBrand.name,
            style: (compact ? textTheme.titleMedium : textTheme.headlineMedium)?.copyWith(
              color: onHero,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        PillChip(label: l10n.brandAiBadge),
      ],
    );
    // Scales down instead of overflowing with big fonts or tiny screens.
    // PT: Encolhe em vez de estourar com fontes grandes ou telas minúsculas.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: compact
          ? wordmark
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.brandKicker,
                  style: textTheme.labelSmall?.copyWith(
                    color: onHero.withValues(alpha: 0.9),
                    letterSpacing: 2.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                wordmark,
                const SizedBox(height: AppSpacing.m),
                Text(l10n.brandTaglineAi, style: textTheme.bodyMedium?.copyWith(color: onHero)),
              ],
            ),
    );
  }
}

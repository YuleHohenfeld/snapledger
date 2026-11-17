import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// A small pill label such as "AI"; [onGradient] styles it for the hero, otherwise for a surface.
/// PT: Um pequeno rótulo em pílula, como "AI"; [onGradient] o estiliza para o hero, senão para uma superfície.
/// Notes: docs/code-notes/app-core.md#brandgradients
class PillChip extends StatelessWidget {
  const PillChip({required this.label, super.key, this.onGradient = true});

  final String label;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final gradients = BrandGradients.of(context);
    final foreground = onGradient ? gradients.onHero : colors.onPrimaryContainer;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: onGradient ? Colors.white.withValues(alpha: 0.16) : colors.primaryContainer,
        shape: StadiumBorder(
          side: BorderSide(color: onGradient ? gradients.frameColor : colors.primary.withValues(alpha: 0.4)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s + AppSpacing.xs, vertical: AppSpacing.xs),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

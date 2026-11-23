import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/glow_orb.dart';

/// A centered "nothing here yet": a glowing icon, a headline, a line of help and an optional [action].
/// PT: Um "nada aqui ainda" centralizado: um ícone com brilho, um título, uma linha de ajuda e uma [action] opcional.
/// Notes: docs/code-notes/app-core.md#brandgradients
class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title, required this.body, super.key, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlowOrb(icon: icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.l),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s),
            Text(body, style: text.bodyMedium, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: AppSpacing.l), action!],
          ],
        ),
      ),
    );
  }
}

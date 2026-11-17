import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// One short headline and one supporting line: the whole text hierarchy of an auth screen.
/// PT: Um título curto e uma linha de apoio: toda a hierarquia de texto de uma tela de auth.
/// Notes: docs/code-notes/app-auth.md#design-widgets
class ScreenHeading extends StatelessWidget {
  const ScreenHeading({required this.title, super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

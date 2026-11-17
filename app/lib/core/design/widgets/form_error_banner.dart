import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// A form-level error (one not tied to a field), announced by screen readers when it appears.
/// PT: Um erro do formulário (não ligado a um campo), anunciado por leitores de tela quando aparece.
/// Notes: docs/code-notes/app-auth.md#design-widgets
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(AppSpacing.s),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: colors.onErrorContainer),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

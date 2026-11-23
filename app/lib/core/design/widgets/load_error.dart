import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// A screen could not load: the reason ([message] and [retryLabel], already translated) and a retry button.
/// PT: Uma tela não carregou: o motivo ([message] e [retryLabel], já traduzidos) e um botão de tentar de novo.
/// Notes: docs/code-notes/app-core.md#loaderror
class LoadError extends StatelessWidget {
  const LoadError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
    super.key,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.m),
          OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    ),
  );
}

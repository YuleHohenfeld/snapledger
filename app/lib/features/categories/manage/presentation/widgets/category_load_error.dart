import 'package:flutter/material.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The list could not load: the reason and a retry button.
/// PT: A lista não carregou: o motivo e um botão de tentar de novo.
/// Notes: docs/code-notes/app-categories.md#categorymanagepage
class CategoryLoadError extends StatelessWidget {
  const CategoryLoadError({required this.failure, required this.onRetry, super.key});

  final ApiFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(failureMessage(l10n, failure) ?? l10n.errorUnexpected),
          const SizedBox(height: AppSpacing.m),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.categoryManageRetry)),
        ],
      ),
    );
  }
}

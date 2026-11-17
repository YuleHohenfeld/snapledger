import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/features/auth/password_reset/application/controller/password_reset_controller.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Step 3: the password changed, every device was signed out; the only way on is the login.
/// PT: Passo 3: a senha mudou, todos os aparelhos foram deslogados; o único caminho é o login.
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
class PasswordResetDoneStep extends StatelessWidget {
  const PasswordResetDoneStep({required this.controller, super.key});

  final PasswordResetController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.passwordResetDoneTitle,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.passwordResetDoneBody,
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.l),
        FilledButton(onPressed: controller.onBackToLogin, child: Text(l10n.passwordResetBackToLogin)),
      ],
    );
  }
}

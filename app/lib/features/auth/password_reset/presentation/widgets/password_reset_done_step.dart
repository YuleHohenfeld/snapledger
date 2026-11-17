import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/glow_orb.dart';
import 'package:snapledger/core/design/widgets/gradient_button.dart';
import 'package:snapledger/features/auth/password_reset/application/controller/password_reset_controller.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Last step: the password changed, every device was signed out; the only way on is the login.
/// PT: Último passo: a senha mudou, todos os aparelhos foram deslogados; o único caminho é o login.
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
class PasswordResetDoneStep extends StatelessWidget {
  const PasswordResetDoneStep({required this.controller, super.key});

  final PasswordResetController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final success = SuccessColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.l),
        Center(child: GlowOrb(icon: Icons.check, color: success.success)),
        const SizedBox(height: AppSpacing.l),
        Semantics(
          liveRegion: true,
          header: true,
          child: Text(
            l10n.passwordResetDoneTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          l10n.passwordResetDoneBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xl),
        GradientButton(label: l10n.passwordResetBackToLogin, onPressed: controller.onBackToLogin),
      ],
    );
  }
}

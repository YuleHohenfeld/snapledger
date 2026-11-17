import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/busy_button.dart';
import 'package:snapledger/core/design/widgets/code_field.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/design/widgets/password_field.dart';
import 'package:snapledger/core/design/widgets/resend_code_button.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/auth/_shared/presentation/auth_field_error_text.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/features/auth/password_reset/application/controller/password_reset_controller.dart';
import 'package:snapledger/features/auth/password_reset/application/viewmodel/password_reset_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Step 2: code, new password, "Change password" and the resend button.
/// PT: Passo 2: código, nova senha, "Alterar senha" e o botão de reenviar.
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
class PasswordResetCodeStep extends StatelessWidget {
  const PasswordResetCodeStep({required this.controller, super.key});

  final PasswordResetController controller;

  static const _fields = {'code', 'newPassword'};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.select((PasswordResetViewModel vm) => vm.state);
    final cooldown = context.select((PasswordResetViewModel vm) => vm.cooldownSeconds);
    if (state is! PasswordResetEnterCode) return const SizedBox.shrink();
    final banner = failureMessage(l10n, state.failure, knownFields: _fields);

    return Form(
      key: controller.resetFormKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.passwordResetTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.passwordResetCodeIntro(state.email),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            if (banner != null) ...[
              FormErrorBanner(message: banner),
              const SizedBox(height: AppSpacing.m),
            ],
            CodeField(
              controller: controller.codeField,
              focusNode: controller.codeFocus,
              label: l10n.codeFieldLabel,
              textInputAction: TextInputAction.next,
              validator: (value) => authFieldErrorText(l10n, controller.codeError(value)),
              errorText: fieldErrorMessage(l10n, state.failure, 'code'),
              onChanged: (_) => controller.onFieldEdited(),
              onFieldSubmitted: (_) => controller.onCodeSubmitted(),
            ),
            const SizedBox(height: AppSpacing.s),
            PasswordField(
              controller: controller.newPasswordField,
              focusNode: controller.newPasswordFocus,
              label: l10n.passwordResetNewPasswordLabel,
              prefixIcon: Icons.lock_outline,
              helperText: l10n.registerPasswordHelper(passwordMinBytes),
              visible: controller.passwordVisible,
              onToggleVisibility: controller.togglePasswordVisibility,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              validator: (value) => authFieldErrorText(l10n, controller.passwordError(value)),
              errorText: fieldErrorMessage(l10n, state.failure, 'newPassword'),
              onChanged: (_) => controller.onFieldEdited(),
              onFieldSubmitted: (_) => controller.onSubmitReset(),
            ),
            const SizedBox(height: AppSpacing.l),
            BusyButton(
              label: l10n.passwordResetSubmit,
              busy: state.busy,
              onPressed: controller.onSubmitReset,
            ),
            const SizedBox(height: AppSpacing.s),
            Center(
              child: ResendCodeButton(
                remainingSeconds: cooldown,
                busy: state.busy,
                onPressed: controller.onResend,
              ),
            ),
            Center(
              child: TextButton(
                onPressed: state.busy ? null : controller.onUseDifferentEmail,
                child: Text(l10n.passwordResetUseDifferentEmail),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/design/widgets/gradient_button.dart';
import 'package:snapledger/core/design/widgets/password_field.dart';
import 'package:snapledger/core/design/widgets/screen_heading.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/auth/_shared/presentation/auth_field_error_text.dart';
import 'package:snapledger/features/auth/_shared/presentation/password_requirements.dart';
import 'package:snapledger/features/auth/password_reset/application/controller/password_reset_controller.dart';
import 'package:snapledger/features/auth/password_reset/application/viewmodel/password_reset_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Step 3: "Create a new password", the field with its live checklist and the confirm button.
/// PT: Passo 3: "Crie uma nova senha", o campo com a checklist ao vivo e o botão de confirmar.
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
class PasswordResetNewPasswordStep extends StatelessWidget {
  const PasswordResetNewPasswordStep({required this.controller, super.key});

  final PasswordResetController controller;

  static const _fields = {'newPassword'};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.select((PasswordResetViewModel vm) => vm.state);
    if (state is! PasswordResetNewPassword) return const SizedBox.shrink();
    final banner = failureMessage(l10n, state.failure, knownFields: _fields);

    return Form(
      key: controller.newPasswordFormKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeading(
              title: l10n.passwordResetNewPasswordTitle,
              subtitle: l10n.passwordResetNewPasswordSubtitle,
            ),
            const SizedBox(height: AppSpacing.l),
            if (banner != null) ...[
              FormErrorBanner(message: banner),
              const SizedBox(height: AppSpacing.m),
            ],
            PasswordField(
              controller: controller.newPasswordField,
              focusNode: controller.newPasswordFocus,
              label: l10n.passwordResetNewPasswordLabel,
              prefixIcon: Icons.lock_outline,
              visible: controller.passwordVisible,
              onToggleVisibility: controller.togglePasswordVisibility,
              autofillHints: const [AutofillHints.newPassword],
              autofocus: true,
              textInputAction: TextInputAction.done,
              validator: (value) => authFieldErrorText(l10n, controller.passwordError(value)),
              errorText: fieldErrorMessage(l10n, state.failure, 'newPassword'),
              onChanged: (_) => controller.onFieldEdited(),
              onFieldSubmitted: (_) => controller.onSubmitNewPassword(),
            ),
            const SizedBox(height: AppSpacing.s),
            PasswordRequirements(controller: controller.newPasswordField),
            const SizedBox(height: AppSpacing.l),
            GradientButton(
              label: l10n.passwordResetSubmit,
              busy: state.busy,
              onPressed: controller.onSubmitNewPassword,
            ),
          ],
        ),
      ),
    );
  }
}

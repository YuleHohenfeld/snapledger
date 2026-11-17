import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/app_text_field.dart';
import 'package:snapledger/core/design/widgets/busy_button.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/design/widgets/screen_heading.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/auth/_shared/presentation/auth_field_error_text.dart';
import 'package:snapledger/features/auth/password_reset/application/controller/password_reset_controller.dart';
import 'package:snapledger/features/auth/password_reset/application/viewmodel/password_reset_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Step 1: "Forgot your password?", the email field and "Send code".
/// PT: Passo 1: "Esqueceu a senha?", o campo de email e "Enviar código".
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
class PasswordResetEmailStep extends StatelessWidget {
  const PasswordResetEmailStep({required this.controller, super.key});

  final PasswordResetController controller;

  static const _fields = {'email'};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.select((PasswordResetViewModel vm) => vm.state);
    final step = state is PasswordResetEnterEmail ? state : const PasswordResetEnterEmail();
    final banner = failureMessage(l10n, step.failure, knownFields: _fields);

    return Form(
      key: controller.emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeading(title: l10n.passwordResetTitle, subtitle: l10n.passwordResetEmailIntro),
          const SizedBox(height: AppSpacing.l),
          if (banner != null) ...[
            FormErrorBanner(message: banner),
            const SizedBox(height: AppSpacing.m),
          ],
          AppTextField(
            controller: controller.emailField,
            focusNode: controller.emailFocus,
            label: l10n.loginEmailLabel,
            prefixIcon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            validator: (value) => authFieldErrorText(l10n, controller.emailError(value)),
            errorText: fieldErrorMessage(l10n, step.failure, 'email'),
            onChanged: (_) => controller.onFieldEdited(),
            onFieldSubmitted: (_) => controller.onSubmitEmail(),
          ),
          const SizedBox(height: AppSpacing.l),
          BusyButton(
            label: l10n.passwordResetSendCode,
            busy: step.busy,
            onPressed: controller.onSubmitEmail,
          ),
        ],
      ),
    );
  }
}

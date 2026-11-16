import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/app_text_field.dart';
import 'package:snapledger/core/design/widgets/busy_button.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/design/widgets/password_field.dart';
import 'package:snapledger/core/design/widgets/prompt_link_row.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/auth/_shared/presentation/auth_field_error_text.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/features/auth/register/application/controller/register_controller.dart';
import 'package:snapledger/features/auth/register/application/viewmodel/register_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The register fields, banner and buttons; a taken email and rejected fields show under the field.
/// PT: Os campos, o banner e os botões do cadastro; email já usado e campos rejeitados aparecem sob o campo.
/// Notes: docs/code-notes/app-auth.md#pages
class RegisterForm extends StatelessWidget {
  const RegisterForm({required this.controller, super.key});

  final RegisterController controller;

  static const _fields = {'name', 'email', 'password'};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.select((RegisterViewModel vm) => vm.state);
    final failure = state is RegisterFailed ? state.failure : null;
    final busy = state is RegisterSubmitting || state is RegisterSucceeded;
    final banner = failureMessage(l10n, failure, knownFields: _fields);

    return Form(
      key: controller.formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.registerHeadline,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.registerSubtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            if (banner != null) ...[
              FormErrorBanner(message: banner),
              const SizedBox(height: AppSpacing.m),
            ],
            AppTextField(
              controller: controller.nameField,
              focusNode: controller.nameFocus,
              label: l10n.registerNameLabel,
              prefixIcon: Icons.person_outline,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              validator: (value) => authFieldErrorText(l10n, controller.nameError(value)),
              errorText: fieldErrorMessage(l10n, failure, 'name'),
              onChanged: (_) => controller.onFieldEdited(),
              onFieldSubmitted: (_) => controller.onNameSubmitted(),
            ),
            const SizedBox(height: AppSpacing.m),
            AppTextField(
              controller: controller.emailField,
              focusNode: controller.emailFocus,
              label: l10n.registerEmailLabel,
              prefixIcon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              enableSuggestions: false,
              validator: (value) => authFieldErrorText(l10n, controller.emailError(value)),
              errorText: fieldErrorMessage(l10n, failure, 'email'),
              onChanged: (_) => controller.onFieldEdited(),
              onFieldSubmitted: (_) => controller.onEmailSubmitted(),
            ),
            const SizedBox(height: AppSpacing.m),
            PasswordField(
              controller: controller.passwordField,
              focusNode: controller.passwordFocus,
              label: l10n.registerPasswordLabel,
              prefixIcon: Icons.lock_outline,
              helperText: l10n.registerPasswordHelper(passwordMinBytes),
              visible: controller.passwordVisible,
              onToggleVisibility: controller.togglePasswordVisibility,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              validator: (value) => authFieldErrorText(l10n, controller.passwordError(value)),
              errorText: fieldErrorMessage(l10n, failure, 'password'),
              onChanged: (_) => controller.onFieldEdited(),
              onFieldSubmitted: (_) => controller.onSubmit(),
            ),
            const SizedBox(height: AppSpacing.l),
            BusyButton(label: l10n.registerSubmit, busy: busy, onPressed: controller.onSubmit),
            const SizedBox(height: AppSpacing.s),
            PromptLinkRow(
              prompt: l10n.registerHaveAccountPrompt,
              actionLabel: l10n.registerHaveAccount,
              onPressed: controller.onLoginTapped,
            ),
          ],
        ),
      ),
    );
  }
}

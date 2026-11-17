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
import 'package:snapledger/features/auth/login/application/controller/login_controller.dart';
import 'package:snapledger/features/auth/login/application/viewmodel/login_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The login fields, banner and buttons; field errors go under the field, the rest in the banner.
/// PT: Os campos, o banner e os botões do login; erros de campo vão sob o campo, o resto no banner.
/// Notes: docs/code-notes/app-auth.md#pages
class LoginForm extends StatelessWidget {
  const LoginForm({required this.controller, super.key});

  final LoginController controller;

  static const _fields = {'email', 'password'};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.select((LoginViewModel vm) => vm.state);
    final failure = state is LoginFailed ? state.failure : null;
    final busy = state is LoginSubmitting || state is LoginSucceeded;
    final banner = failureMessage(l10n, failure, knownFields: _fields);

    return Form(
      key: controller.formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.loginHeadline,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.loginSubtitle,
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
              controller: controller.emailField,
              focusNode: controller.emailFocus,
              label: l10n.loginEmailLabel,
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
              label: l10n.loginPasswordLabel,
              prefixIcon: Icons.lock_outline,
              visible: controller.passwordVisible,
              onToggleVisibility: controller.togglePasswordVisibility,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              validator: (value) => authFieldErrorText(l10n, controller.passwordError(value)),
              errorText: fieldErrorMessage(l10n, failure, 'password'),
              onChanged: (_) => controller.onFieldEdited(),
              onFieldSubmitted: (_) => controller.onSubmit(),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: controller.onForgotPasswordTapped,
                child: Text(l10n.loginForgotPassword),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            BusyButton(label: l10n.loginSubmit, busy: busy, onPressed: controller.onSubmit),
            const SizedBox(height: AppSpacing.s),
            PromptLinkRow(
              prompt: l10n.loginNoAccount,
              actionLabel: l10n.loginCreateAccount,
              onPressed: controller.onCreateAccountTapped,
            ),
          ],
        ),
      ),
    );
  }
}

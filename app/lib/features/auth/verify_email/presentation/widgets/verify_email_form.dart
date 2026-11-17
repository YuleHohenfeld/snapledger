import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/busy_button.dart';
import 'package:snapledger/core/design/widgets/code_field.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/design/widgets/resend_code_button.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/auth/_shared/presentation/auth_field_error_text.dart';
import 'package:snapledger/features/auth/verify_email/application/controller/verify_email_controller.dart';
import 'package:snapledger/features/auth/verify_email/application/viewmodel/verify_email_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The body of the Verify email screen for each state: loading, load error, code form, verified.
/// PT: O corpo da tela de verificar email para cada estado: carregando, erro, formulário do código, verificado.
/// Notes: docs/code-notes/app-auth.md#verifyemailviewmodel
class VerifyEmailForm extends StatelessWidget {
  const VerifyEmailForm({required this.controller, super.key});

  final VerifyEmailController controller;

  static const _fields = {'code'};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = context.select((VerifyEmailViewModel vm) => vm.state);
    final cooldown = context.select((VerifyEmailViewModel vm) => vm.cooldownSeconds);
    final title = Text(
      l10n.verifyEmailTitle,
      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    );
    final leaveLabel = controller.afterRegister ? l10n.verifyEmailSkip : l10n.verifyEmailBack;
    final muted =theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return switch (state) {
      VerifyEmailLoading() => const Center(child: CircularProgressIndicator()),
      VerifyEmailLoadFailed(:final failure) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormErrorBanner(message: failureMessage(l10n, failure) ?? l10n.errorUnexpected),
          const SizedBox(height: AppSpacing.m),
          OutlinedButton(onPressed: controller.start, child: Text(l10n.profileRetry)),
          Center(
            child: TextButton(onPressed: controller.onSkipTapped, child: Text(leaveLabel)),
          ),
        ],
      ),
      VerifyEmailVerified() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(l10n.verifyEmailSuccess, style: theme.textTheme.headlineSmall),
          ),
          const SizedBox(height: AppSpacing.l),
          FilledButton(onPressed: controller.onContinueTapped, child: Text(l10n.verifyEmailContinue)),
        ],
      ),
      VerifyEmailReady(:final email, :final busy, :final failure) => Form(
        key: controller.formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: AppSpacing.xs),
              Text(l10n.verifyEmailIntro(email), style: muted),
              const SizedBox(height: AppSpacing.l),
              if (failureMessage(l10n, failure, knownFields: _fields) case final banner?) ...[
                FormErrorBanner(message: banner),
                const SizedBox(height: AppSpacing.m),
              ],
              CodeField(
                controller: controller.codeField,
                focusNode: controller.codeFocus,
                label: l10n.codeFieldLabel,
                textInputAction: TextInputAction.done,
                validator: (value) => authFieldErrorText(l10n, controller.codeError(value)),
                errorText: fieldErrorMessage(l10n, failure, 'code'),
                onChanged: (_) => controller.onFieldEdited(),
                onFieldSubmitted: (_) => controller.onSubmit(),
              ),
              const SizedBox(height: AppSpacing.l),
              BusyButton(label: l10n.verifyEmailSubmit, busy: busy, onPressed: controller.onSubmit),
              const SizedBox(height: AppSpacing.s),
              Center(
                child: ResendCodeButton(
                  remainingSeconds: cooldown,
                  busy: busy,
                  onPressed: controller.onResend,
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: controller.onSkipTapped,
                  child: Text(leaveLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    };
  }
}

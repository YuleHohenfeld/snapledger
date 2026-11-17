import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/auth/_shared/presentation/code_verification_view.dart';
import 'package:snapledger/features/auth/verify_email/application/controller/verify_email_controller.dart';
import 'package:snapledger/features/auth/verify_email/application/viewmodel/verify_email_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The body of the Verify email screen for each state: loading, load error, code boxes, already verified.
/// PT: O corpo da tela de verificar email para cada estado: carregando, erro, caixas do código, já verificado.
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

    return switch (state) {
      VerifyEmailLoading() => const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      VerifyEmailLoadFailed(:final failure) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormErrorBanner(message: failureMessage(l10n, failure) ?? l10n.errorUnexpected),
          const SizedBox(height: AppSpacing.m),
          OutlinedButton(onPressed: controller.start, child: Text(l10n.profileRetry)),
        ],
      ),
      // Only when the profile already says verified; after a typed code the Controller leaves at once.
      // PT: Só quando o perfil já diz verificado; após um código digitado o Controller sai na hora.
      VerifyEmailVerified() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.verifyEmailSuccess,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          FilledButton(onPressed: controller.onContinueTapped, child: Text(l10n.verifyEmailContinue)),
        ],
      ),
      VerifyEmailReady() => CodeVerificationView(
        email: state.email,
        status: state.status,
        codeController: controller.codeField,
        codeFocus: controller.codeFocus,
        cooldownSeconds: cooldown,
        resending: state.resending,
        errorText: fieldErrorMessage(l10n, state.failure, 'code'),
        banner: failureMessage(l10n, state.failure, knownFields: _fields),
        onCodeChanged: controller.onCodeEdited,
        onCodeCompleted: controller.onCodeCompleted,
        onResend: controller.onResend,
      ),
    };
  }
}

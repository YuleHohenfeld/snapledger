import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/auth/_shared/presentation/code_verification_view.dart';
import 'package:snapledger/features/auth/password_reset/application/controller/password_reset_controller.dart';
import 'package:snapledger/features/auth/password_reset/application/viewmodel/password_reset_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Step 2: the shared "Check your email" code screen; the failure texts are localized here.
/// PT: Passo 2: a tela de código "Confira seu email" compartilhada; os textos de falha são traduzidos aqui.
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
class PasswordResetCodeStep extends StatelessWidget {
  const PasswordResetCodeStep({required this.controller, super.key});

  final PasswordResetController controller;

  static const _fields = {'code'};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.select((PasswordResetViewModel vm) => vm.state);
    final cooldown = context.select((PasswordResetViewModel vm) => vm.cooldownSeconds);
    if (state is! PasswordResetEnterCode) return const SizedBox.shrink();
    return CodeVerificationView(
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
    );
  }
}

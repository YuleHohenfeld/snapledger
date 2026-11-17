import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/features/auth/verify_email/application/viewmodel/verify_email_view_model.dart';

/// Screen-only state of the Verify email screen (the code field) and its user events.
/// PT: Estado só da tela de verificar email (o campo do código) e seus eventos.
/// Notes: docs/code-notes/app-auth.md#verifyemailviewmodel
class VerifyEmailController {
  VerifyEmailController({required this._viewModel, required this._navigator});

  final VerifyEmailViewModel _viewModel;
  final AppNavigator _navigator;

  final TextEditingController codeField = TextEditingController();
  final FocusNode codeFocus = FocusNode();
  bool _disposed = false;

  /// Whether the screen opened right after register ("Skip for now") or from the profile ("Back").
  /// PT: Se a tela abriu logo após o cadastro ("Pular por agora") ou pelo perfil ("Voltar").
  bool get afterRegister => _viewModel.afterRegister;

  void start() => unawaited(_viewModel.start());

  /// The 6th digit was typed: confirms; a failure clears the boxes, a success leaves the screen.
  /// PT: O 6º dígito foi digitado: confirma; uma falha limpa as caixas, um sucesso sai da tela.
  Future<void> onCodeCompleted(String code) async {
    if (validateCode(code) != null) return;
    await _viewModel.confirm(code);
    if (_disposed) return;
    final state = _viewModel.state;
    if (state is VerifyEmailReady && state.failure != null) codeField.clear();
    if (state is VerifyEmailVerified) {
      codeField.clear();
      onContinueTapped();
    }
  }

  void onResend() {
    codeField.clear();
    unawaited(_viewModel.sendCode());
  }

  void onCodeEdited(String _) => _viewModel.clearFailure();

  void onSkipTapped() {
    _viewModel.skip();
    _leave();
  }

  /// "Continue" after a successful verification: the same exit as skipping.
  /// PT: "Continuar" após uma verificação bem-sucedida: a mesma saída de pular.
  void onContinueTapped() => onSkipTapped();

  // After register the screen replaced the whole stack (summary is next); from the profile it was pushed.
  // PT: Após o cadastro a tela substituiu a pilha toda (resumo é o próximo); vinda do perfil, foi empilhada.
  // Notes: docs/code-notes/app-auth.md#pending-verification
  void _leave() {
    if (_viewModel.afterRegister) {
      _navigator.goTo(AppRoute.summary);
    } else {
      _navigator.pop();
    }
  }

  void dispose() {
    _disposed = true;
    codeField.dispose();
    codeFocus.dispose();
  }
}

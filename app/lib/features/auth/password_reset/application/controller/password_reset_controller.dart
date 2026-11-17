import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/features/auth/password_reset/application/viewmodel/password_reset_view_model.dart';

/// Screen-only state of the password reset (fields of both steps) and its user events.
/// PT: Estado só da tela de troca de senha (campos dos dois passos) e seus eventos.
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
class PasswordResetController {
  PasswordResetController({required this._viewModel, required this._navigator});

  final PasswordResetViewModel _viewModel;
  final AppNavigator _navigator;

  final GlobalKey<FormState> emailFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> resetFormKey = GlobalKey<FormState>();
  final TextEditingController emailField = TextEditingController();
  final TextEditingController codeField = TextEditingController();
  final TextEditingController newPasswordField = TextEditingController();
  final FocusNode emailFocus = FocusNode();
  final FocusNode codeFocus = FocusNode();
  final FocusNode newPasswordFocus = FocusNode();

  /// Whether the new password is shown; hidden by default.
  /// PT: Se a nova senha está visível; oculta por padrão.
  final ValueNotifier<bool> passwordVisible = ValueNotifier<bool>(false);

  AuthFieldError? emailError(String? value) => validateEmail(value);

  AuthFieldError? codeError(String? value) => validateCode(value);

  AuthFieldError? passwordError(String? value) => validateRegisterPassword(value);

  void togglePasswordVisibility() => passwordVisible.value = !passwordVisible.value;

  void onCodeSubmitted() => newPasswordFocus.requestFocus();

  /// Step 1: shows the field error and stops when the email is invalid; otherwise asks for the code.
  /// PT: Passo 1: mostra o erro do campo e para quando o email é inválido; senão pede o código.
  Future<void> onSubmitEmail() async {
    emailFormKey.currentState?.validate();
    if (emailError(emailField.text) != null) return;
    await _viewModel.requestCode(emailField.text);
  }

  /// Step 2: shows the field errors and stops when one is invalid; otherwise confirms.
  /// PT: Passo 2: mostra os erros dos campos e para quando um é inválido; senão confirma.
  Future<void> onSubmitReset() async {
    resetFormKey.currentState?.validate();
    if (codeError(codeField.text) != null || passwordError(newPasswordField.text) != null) return;
    await _viewModel.confirm(code: codeField.text, newPassword: newPasswordField.text);
    if (_viewModel.state is PasswordResetDone) _clearSecrets();
  }

  void onResend() => unawaited(_viewModel.resend());

  /// Back to the email step; the email stays in its field so the user can edit it.
  /// PT: Volta ao passo do email; o email continua no campo para o usuário editá-lo.
  /// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
  void onUseDifferentEmail() {
    codeField.clear();
    newPasswordField.clear();
    _viewModel.backToEmail();
  }

  void onBackToLogin() {
    _clearSecrets();
    _navigator.goTo(AppRoute.login);
  }

  // The code and the new password do not outlive the flow in memory.
  // PT: O código e a nova senha não sobrevivem ao fluxo na memória.
  void _clearSecrets() {
    codeField.clear();
    newPasswordField.clear();
  }

  /// Any edit removes the old error from the screen.
  /// PT: Qualquer edição tira da tela o erro antigo.
  void onFieldEdited() => _viewModel.clearFailure();

  void dispose() {
    emailField.dispose();
    codeField.dispose();
    newPasswordField.dispose();
    emailFocus.dispose();
    codeFocus.dispose();
    newPasswordFocus.dispose();
    passwordVisible.dispose();
  }
}

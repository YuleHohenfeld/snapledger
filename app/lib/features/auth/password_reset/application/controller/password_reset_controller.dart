import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/features/auth/password_reset/application/viewmodel/password_reset_view_model.dart';

/// Screen-only state of the password reset (fields of the three steps) and its user events.
/// PT: Estado só da tela de troca de senha (campos dos três passos) e seus eventos.
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
class PasswordResetController {
  PasswordResetController({required this._viewModel, required this._navigator});

  final PasswordResetViewModel _viewModel;
  final AppNavigator _navigator;

  final GlobalKey<FormState> emailFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> newPasswordFormKey = GlobalKey<FormState>();
  final TextEditingController emailField = TextEditingController();
  final TextEditingController codeField = TextEditingController();
  final TextEditingController newPasswordField = TextEditingController();
  final FocusNode emailFocus = FocusNode();
  final FocusNode codeFocus = FocusNode();
  final FocusNode newPasswordFocus = FocusNode();

  /// Whether the new password is shown; hidden by default.
  /// PT: Se a nova senha está visível; oculta por padrão.
  final ValueNotifier<bool> passwordVisible = ValueNotifier<bool>(false);

  bool _disposed = false;

  AuthFieldError? emailError(String? value) => validateEmail(value);

  AuthFieldError? passwordError(String? value) => validateRegisterPassword(value);

  void togglePasswordVisibility() => passwordVisible.value = !passwordVisible.value;

  /// Step 1: shows the field error and stops when the email is invalid; otherwise asks for the code.
  /// PT: Passo 1: mostra o erro do campo e para quando o email é inválido; senão pede o código.
  Future<void> onSubmitEmail() async {
    emailFormKey.currentState?.validate();
    if (emailError(emailField.text) != null) return;
    await _viewModel.requestCode(emailField.text);
  }

  /// Step 2: the 6th digit was typed. A failed check clears the boxes so the user can retype.
  /// PT: Passo 2: o 6º dígito foi digitado. Uma checagem que falha limpa as caixas para o usuário redigitar.
  Future<void> onCodeCompleted(String code) async {
    if (validateCode(code) != null) return;
    await _viewModel.verifyCode(code);
    if (_disposed) return;
    final state = _viewModel.state;
    if (state is! PasswordResetEnterCode || state.failure != null) codeField.clear();
  }

  /// The user types again after an error: the red state goes away.
  /// PT: O usuário volta a digitar após um erro: o estado vermelho some.
  void onCodeEdited(String _) => _viewModel.clearFailure();

  void onResend() {
    codeField.clear();
    unawaited(_viewModel.resend());
  }

  /// Step 3: shows the field error and stops when the password is invalid; otherwise confirms.
  /// PT: Passo 3: mostra o erro do campo e para quando a senha é inválida; senão confirma.
  Future<void> onSubmitNewPassword() async {
    newPasswordFormKey.currentState?.validate();
    if (passwordError(newPasswordField.text) != null) return;
    await _viewModel.confirm(newPasswordField.text);
    if (_disposed) return;
    // Done or back at step 1 (expired token): the password does not outlive the step.
    // PT: Concluído ou de volta ao passo 1 (token expirado): a senha não sobrevive ao passo.
    if (_viewModel.state is PasswordResetDone || _viewModel.state is PasswordResetEnterEmail) {
      newPasswordField.clear();
    }
  }

  /// The app bar arrow: step 1 leaves to the login; steps 2 and 3 go back to the email step.
  /// PT: A seta da app bar: o passo 1 sai para o login; os passos 2 e 3 voltam ao passo do email.
  /// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
  void onBack() {
    if (_viewModel.state is PasswordResetEnterEmail) {
      _navigator.goTo(AppRoute.login);
      return;
    }
    _clearSecrets();
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
    _disposed = true;
    emailField.dispose();
    codeField.dispose();
    newPasswordField.dispose();
    emailFocus.dispose();
    codeFocus.dispose();
    newPasswordFocus.dispose();
    passwordVisible.dispose();
  }
}

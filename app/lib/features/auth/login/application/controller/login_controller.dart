import 'package:flutter/widgets.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/features/auth/login/application/viewmodel/login_view_model.dart';

/// Screen-only state of the login form and its user events; it never navigates on success.
/// PT: Estado só da tela do formulário de login e seus eventos; nunca navega no sucesso.
/// Notes: docs/code-notes/app-auth.md#logincontroller
class LoginController {
  LoginController({required this._viewModel, required this._navigator}) {
    _viewModel.addListener(_clearPasswordOnWrongCredentials);
  }

  final LoginViewModel _viewModel;
  final AppNavigator _navigator;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController emailField = TextEditingController();
  final TextEditingController passwordField = TextEditingController();
  final FocusNode emailFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  /// Whether the password is shown; hidden by default.
  /// PT: Se a senha está visível; oculta por padrão.
  final ValueNotifier<bool> passwordVisible = ValueNotifier<bool>(false);

  AuthFieldError? emailError(String? value) => validateEmail(value);

  AuthFieldError? passwordError(String? value) => validateLoginPassword(value);

  void togglePasswordVisibility() => passwordVisible.value = !passwordVisible.value;

  void onEmailSubmitted() => passwordFocus.requestFocus();

  /// Shows the field errors and stops when a field is invalid; otherwise submits.
  /// PT: Mostra os erros dos campos e para quando um campo é inválido; senão envia.
  /// Notes: docs/code-notes/app-auth.md#onsubmit
  Future<void> onSubmit() async {
    formKey.currentState?.validate();
    if (emailError(emailField.text) != null || passwordError(passwordField.text) != null) return;
    await _viewModel.submit(email: emailField.text, password: passwordField.text);
  }

  void onCreateAccountTapped() => _navigator.goTo(AppRoute.register);

  void onForgotPasswordTapped() => _navigator.goTo(AppRoute.passwordReset);

  /// Any edit removes the old error from the screen.
  /// PT: Qualquer edição tira da tela o erro antigo.
  /// Notes: docs/code-notes/app-auth.md#onsubmit
  void onFieldEdited() => _viewModel.clearFailure();

  // A wrong password is not worth keeping in the field; a network or server error keeps it for a retry.
  // PT: Uma senha errada não vale ficar no campo; um erro de rede ou servidor a mantém para tentar de novo.
  // Notes: docs/code-notes/app-auth.md#onsubmit
  void _clearPasswordOnWrongCredentials() {
    if (_viewModel.state case LoginFailed(
      failure: ProblemFailure(type: ProblemType.invalidCredentials),
    )) {
      passwordField.clear();
    }
  }

  void dispose() {
    _viewModel.removeListener(_clearPasswordOnWrongCredentials);
    emailField.dispose();
    passwordField.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    passwordVisible.dispose();
  }
}

import 'package:flutter/widgets.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/features/auth/register/application/viewmodel/register_view_model.dart';

/// Screen-only state of the register form and its user events; it never navigates on success.
/// PT: Estado só da tela do formulário de cadastro e seus eventos; nunca navega no sucesso.
/// Notes: docs/code-notes/app-auth.md#registercontroller
class RegisterController {
  RegisterController({required this._viewModel, required this._navigator});

  final RegisterViewModel _viewModel;
  final AppNavigator _navigator;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController nameField = TextEditingController();
  final TextEditingController emailField = TextEditingController();
  final TextEditingController passwordField = TextEditingController();
  final FocusNode nameFocus = FocusNode();
  final FocusNode emailFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  /// Whether the password is shown; hidden by default.
  /// PT: Se a senha está visível; oculta por padrão.
  final ValueNotifier<bool> passwordVisible = ValueNotifier<bool>(false);

  AuthFieldError? nameError(String? value) => validateName(value);

  AuthFieldError? emailError(String? value) => validateEmail(value);

  AuthFieldError? passwordError(String? value) => validateRegisterPassword(value);

  void togglePasswordVisibility() => passwordVisible.value = !passwordVisible.value;

  void onNameSubmitted() => emailFocus.requestFocus();

  void onEmailSubmitted() => passwordFocus.requestFocus();

  /// Shows the field errors and stops when a field is invalid; otherwise submits.
  /// PT: Mostra os erros dos campos e para quando um campo é inválido; senão envia.
  /// Notes: docs/code-notes/app-auth.md#onsubmit
  Future<void> onSubmit() async {
    formKey.currentState?.validate();
    if (nameError(nameField.text) != null ||
        emailError(emailField.text) != null ||
        passwordError(passwordField.text) != null) {
      return;
    }
    await _viewModel.submit(
      name: nameField.text,
      email: emailField.text,
      password: passwordField.text,
    );
  }

  void onLoginTapped() => _navigator.goTo(AppRoute.login);

  /// Any edit removes the old error from the screen.
  /// PT: Qualquer edição tira da tela o erro antigo.
  /// Notes: docs/code-notes/app-auth.md#onsubmit
  void onFieldEdited() => _viewModel.clearFailure();

  void dispose() {
    nameField.dispose();
    emailField.dispose();
    passwordField.dispose();
    nameFocus.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    passwordVisible.dispose();
  }
}

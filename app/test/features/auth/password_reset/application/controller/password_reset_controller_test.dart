import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/features/auth/password_reset/application/controller/password_reset_controller.dart';
import 'package:snapledger/features/auth/password_reset/application/viewmodel/password_reset_view_model.dart';

import '../../../../../support/fake_auth_repository.dart';
import '../../../../../support/fake_navigator.dart';

void main() {
  // GlobalKey.currentState needs a binding, even with no Form mounted.
  // PT: O GlobalKey.currentState precisa de um binding, mesmo sem Form montado.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthRepository auth;
  late FakeNavigator navigator;
  late PasswordResetViewModel viewModel;
  late PasswordResetController controller;

  setUp(() {
    auth = FakeAuthRepository();
    navigator = FakeNavigator();
    viewModel = PasswordResetViewModel(auth: auth);
    controller = PasswordResetController(viewModel: viewModel, navigator: navigator);
  });

  tearDown(() {
    controller.dispose();
    viewModel.dispose();
  });

  test('validates the email, code and new password', () {
    expect(controller.emailError(''), AuthFieldError.required);
    expect(controller.emailError('ana'), AuthFieldError.emailInvalid);
    expect(controller.emailError('ana@example.com'), isNull);
    expect(controller.codeError('12345'), AuthFieldError.codeInvalid);
    expect(controller.codeError('042917'), isNull);
    expect(controller.passwordError('short'), AuthFieldError.passwordTooShort);
    expect(controller.passwordError('fake-new-password'), isNull);
  });

  test('an invalid email is not sent', () async {
    controller.emailField.text = 'not-an-email';

    await controller.onSubmitEmail();

    expect(auth.resetRequests, isEmpty);
  });

  test('a valid email asks for the code', () async {
    controller.emailField.text = 'ana@example.com';

    await controller.onSubmitEmail();

    expect(auth.resetRequests.single.email, 'ana@example.com');
    expect(viewModel.state, isA<PasswordResetEnterCode>());
  });

  test('an invalid code or password is not confirmed', () async {
    controller.emailField.text = 'ana@example.com';
    await controller.onSubmitEmail();

    controller.codeField.text = '123';
    controller.newPasswordField.text = 'fake-new-password';
    await controller.onSubmitReset();
    controller.codeField.text = '042917';
    controller.newPasswordField.text = 'short';
    await controller.onSubmitReset();

    expect(auth.resetConfirms, isEmpty);
  });

  test('valid code and password confirm the reset', () async {
    controller.emailField.text = 'ana@example.com';
    await controller.onSubmitEmail();
    controller.codeField.text = '042917';
    controller.newPasswordField.text = 'fake-new-password';

    await controller.onSubmitReset();

    expect(auth.resetConfirms.single.code, '042917');
    expect(viewModel.state, isA<PasswordResetDone>());
  });

  test('a finished reset clears the code and the new password from memory', () async {
    controller.emailField.text = 'ana@example.com';
    await controller.onSubmitEmail();
    controller.codeField.text = '042917';
    controller.newPasswordField.text = 'fake-new-password';

    await controller.onSubmitReset();

    expect(viewModel.state, isA<PasswordResetDone>());
    expect(controller.codeField.text, isEmpty);
    expect(controller.newPasswordField.text, isEmpty);
  });

  test('back to login clears the secret fields too', () {
    controller.codeField.text = '042917';
    controller.newPasswordField.text = 'fake-new-password';

    controller.onBackToLogin();

    expect(controller.codeField.text, isEmpty);
    expect(controller.newPasswordField.text, isEmpty);
  });

  test('use a different email returns to step 1 keeping the email, dropping the secrets', () async {
    controller.emailField.text = 'ana@example.com';
    await controller.onSubmitEmail();
    controller.codeField.text = '042917';
    controller.newPasswordField.text = 'fake-new-password';

    controller.onUseDifferentEmail();

    expect(viewModel.state, isA<PasswordResetEnterEmail>());
    expect(controller.emailField.text, 'ana@example.com');
    expect(controller.codeField.text, isEmpty);
    expect(controller.newPasswordField.text, isEmpty);
  });

  test('editing a field clears the old failure', () async {
    auth.failure = const NetworkFailure();
    controller.emailField.text = 'ana@example.com';
    await controller.onSubmitEmail();
    expect(viewModel.state, isA<PasswordResetEnterEmail>().having((s) => s.failure, 'f', isNotNull));

    controller.onFieldEdited();

    expect(viewModel.state, isA<PasswordResetEnterEmail>().having((s) => s.failure, 'f', isNull));
  });

  test('back to login is a navigation intent', () {
    controller.onBackToLogin();

    expect(navigator.wentTo, [AppRoute.login]);
  });

  test('toggles the new password visibility', () {
    expect(controller.passwordVisible.value, isFalse);
    controller.togglePasswordVisibility();
    expect(controller.passwordVisible.value, isTrue);
  });
}

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
    viewModel = PasswordResetViewModel(auth: auth, successPause: Duration.zero);
    controller = PasswordResetController(viewModel: viewModel, navigator: navigator);
  });

  tearDown(() {
    controller.dispose();
    viewModel.dispose();
  });

  test('validates the email and new password', () {
    expect(controller.emailError(''), AuthFieldError.required);
    expect(controller.emailError('ana'), AuthFieldError.emailInvalid);
    expect(controller.emailError('ana@example.com'), isNull);
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

  Future<void> reachNewPasswordStep() async {
    controller.emailField.text = 'ana@example.com';
    await controller.onSubmitEmail();
    controller.codeField.text = '042917';
    await controller.onCodeCompleted('042917');
  }

  test('a malformed code is not verified', () async {
    controller.emailField.text = 'ana@example.com';
    await controller.onSubmitEmail();

    await controller.onCodeCompleted('123');

    expect(auth.resetVerifies, isEmpty);
  });

  test('a completed code is verified, advances and clears the boxes', () async {
    await reachNewPasswordStep();

    expect(auth.resetVerifies.single.code, '042917');
    expect(viewModel.state, isA<PasswordResetNewPassword>());
    expect(controller.codeField.text, isEmpty);
  });

  test('a refused code clears the boxes for retyping', () async {
    auth.verifyFailure = const ProblemFailure(status: 400, type: ProblemType.invalidCode);
    controller.emailField.text = 'ana@example.com';
    await controller.onSubmitEmail();
    controller.codeField.text = '000000';

    await controller.onCodeCompleted('000000');

    expect(controller.codeField.text, isEmpty);
    expect(viewModel.state, isA<PasswordResetEnterCode>());
  });

  test('typing after an error removes the error', () async {
    auth.verifyFailure = const ProblemFailure(status: 400, type: ProblemType.invalidCode);
    controller.emailField.text = 'ana@example.com';
    await controller.onSubmitEmail();
    await controller.onCodeCompleted('000000');

    controller.onCodeEdited('1');

    expect(viewModel.state, isA<PasswordResetEnterCode>().having((s) => s.failure, 'f', isNull));
  });

  test('a weak new password is not confirmed', () async {
    await reachNewPasswordStep();
    controller.newPasswordField.text = 'short';

    await controller.onSubmitNewPassword();

    expect(auth.resetConfirms, isEmpty);
  });

  test('a valid new password confirms with the reset token', () async {
    await reachNewPasswordStep();
    controller.newPasswordField.text = 'fake-new-password';

    await controller.onSubmitNewPassword();

    expect(auth.resetConfirms.single.resetToken, 'fake-reset-token');
    expect(viewModel.state, isA<PasswordResetDone>());
  });

  test('a finished reset clears the new password from memory', () async {
    await reachNewPasswordStep();
    controller.newPasswordField.text = 'fake-new-password';

    await controller.onSubmitNewPassword();

    expect(controller.newPasswordField.text, isEmpty);
  });

  test('an expired reset session returns to step 1 and clears the password', () async {
    await reachNewPasswordStep();
    auth.confirmFailure = const ProblemFailure(status: 400, type: ProblemType.invalidResetToken);
    controller.newPasswordField.text = 'fake-new-password';

    await controller.onSubmitNewPassword();

    expect(viewModel.state, isA<PasswordResetEnterEmail>().having((s) => s.failure, 'f', isNotNull));
    expect(controller.newPasswordField.text, isEmpty);
  });

  test('back to login clears the secret fields too', () {
    controller.codeField.text = '042917';
    controller.newPasswordField.text = 'fake-new-password';

    controller.onBackToLogin();

    expect(controller.codeField.text, isEmpty);
    expect(controller.newPasswordField.text, isEmpty);
  });

  test('back from step 2 returns to step 1 keeping the email, dropping the secrets', () async {
    controller.emailField.text = 'ana@example.com';
    await controller.onSubmitEmail();
    controller.codeField.text = '042917';

    controller.onBack();

    expect(viewModel.state, isA<PasswordResetEnterEmail>());
    expect(controller.emailField.text, 'ana@example.com');
    expect(controller.codeField.text, isEmpty);
    expect(navigator.wentTo, isEmpty);
  });

  test('back from step 3 returns to step 1 and drops the token', () async {
    await reachNewPasswordStep();

    controller.onBack();

    expect(viewModel.state, isA<PasswordResetEnterEmail>());
  });

  test('back from step 1 goes to the login', () {
    controller.onBack();

    expect(navigator.wentTo, [AppRoute.login]);
  });

  test('resend clears the boxes and asks for another code', () async {
    controller.emailField.text = 'ana@example.com';
    await controller.onSubmitEmail();
    controller.codeField.text = '123';

    controller.onResend();

    expect(controller.codeField.text, isEmpty);
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

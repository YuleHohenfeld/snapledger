import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/features/auth/login/application/controller/login_controller.dart';
import 'package:snapledger/features/auth/login/application/viewmodel/login_view_model.dart';

import '../../../../../support/fake_auth_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/fake_session_refresher.dart';

void main() {
  // GlobalKey.currentState needs a binding, even with no Form mounted.
  // PT: O GlobalKey.currentState precisa de um binding, mesmo sem Form montado.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthRepository auth;
  late SessionNotifier session;
  late FakeNavigator navigator;
  late PendingVerification pending;
  late LoginViewModel viewModel;
  late LoginController controller;

  setUp(() {
    auth = FakeAuthRepository();
    session = inMemorySession().session;
    navigator = FakeNavigator();
    pending = PendingVerification(session: session);
    viewModel = LoginViewModel(auth: auth, session: session, pending: pending);
    controller = LoginController(viewModel: viewModel, navigator: navigator);
  });

  tearDown(() {
    viewModel.dispose();
    pending.dispose();
    session.dispose();
  });

  test('submits the typed email and password', () async {
    controller.emailField.text = 'ana@example.com';
    controller.passwordField.text = 'fake-password';

    await controller.onSubmit();

    expect(auth.logins.single.email, 'ana@example.com');
    expect(auth.logins.single.password, 'fake-password');
    expect(viewModel.state, isA<LoginSucceeded>());
  });

  for (final (label, email, password) in [
    ('an empty email', '', 'fake-password'),
    ('an email without @', 'not-an-email', 'fake-password'),
    ('an empty password', 'ana@example.com', ''),
    ('a password over 72 bytes', 'ana@example.com', 'a' * 73),
  ]) {
    test('$label blocks the submit', () async {
      controller.emailField.text = email;
      controller.passwordField.text = password;

      await controller.onSubmit();

      expect(auth.logins, isEmpty);
      expect(viewModel.state, isA<LoginIdle>());
    });
  }

  group('after a failed login', () {
    Future<void> failWith(Exception failure) async {
      auth.failure = failure;
      controller.emailField.text = 'ana@example.com';
      controller.passwordField.text = 'fake-password';
      await controller.onSubmit();
    }

    test('wrong credentials clear the password but keep the email', () async {
      await failWith(const ProblemFailure(status: 401, type: ProblemType.invalidCredentials));

      expect(controller.passwordField.text, isEmpty);
      expect(controller.emailField.text, 'ana@example.com');
    });

    for (final failure in <Exception>[
      const NetworkFailure(),
      const ProblemFailure(status: 500, type: ProblemType.internalError),
    ]) {
      test('$failure keeps the password for a retry', () async {
        await failWith(failure);

        expect(controller.passwordField.text, 'fake-password');
      });
    }

    test('editing a field clears the failure', () async {
      await failWith(const NetworkFailure());

      controller.onFieldEdited();

      expect(viewModel.state, isA<LoginIdle>());
    });
  });

  test('uses the login rules: no minimum password length', () {
    expect(controller.passwordError('a'), isNull);
    expect(controller.passwordError(''), AuthFieldError.required);
    expect(controller.emailError('josé@example.com'), AuthFieldError.emailInvalid);
  });

  test('the password starts hidden and toggles', () {
    expect(controller.passwordVisible.value, isFalse);

    controller.togglePasswordVisibility();
    expect(controller.passwordVisible.value, isTrue);

    controller.togglePasswordVisibility();
    expect(controller.passwordVisible.value, isFalse);
  });

  test('"create account" is a navigation intent to register', () {
    controller.onCreateAccountTapped();

    expect(navigator.wentTo, [AppRoute.register]);
  });

  test('never navigates on success: the router redirect does', () async {
    controller.emailField.text = 'ana@example.com';
    controller.passwordField.text = 'fake-password';

    await controller.onSubmit();

    expect(navigator.wentTo, isEmpty);
    expect(navigator.pushed, isEmpty);
  });

  test('dispose releases the text fields, focus nodes and the visibility notifier', () {
    final local = LoginController(viewModel: viewModel, navigator: navigator)..dispose();

    // A disposed ChangeNotifier refuses new listeners (debug assertion).
    // PT: Um ChangeNotifier descartado recusa novos listeners (asserção de debug).
    for (final notifier in <ChangeNotifier>[
      local.emailField,
      local.passwordField,
      local.emailFocus,
      local.passwordFocus,
      local.passwordVisible,
    ]) {
      expect(() => notifier.addListener(() {}), throwsFlutterError);
    }
  });
}

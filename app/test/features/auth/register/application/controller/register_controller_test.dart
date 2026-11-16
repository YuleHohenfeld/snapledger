import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/features/auth/register/application/controller/register_controller.dart';
import 'package:snapledger/features/auth/register/application/viewmodel/register_view_model.dart';

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
  late RegisterViewModel viewModel;
  late RegisterController controller;

  setUp(() {
    auth = FakeAuthRepository();
    session = inMemorySession().session;
    navigator = FakeNavigator();
    viewModel = RegisterViewModel(auth: auth, session: session);
    controller = RegisterController(viewModel: viewModel, navigator: navigator);
  });

  tearDown(() {
    viewModel.dispose();
    session.dispose();
  });

  void fill({
    String name = 'Ana Souza',
    String email = 'ana@example.com',
    String password = 'fake-password',
  }) {
    controller.nameField.text = name;
    controller.emailField.text = email;
    controller.passwordField.text = password;
  }

  test('submits the typed name, email and password', () async {
    fill();

    await controller.onSubmit();

    final request = auth.registers.single;
    expect(request.name, 'Ana Souza');
    expect(request.email, 'ana@example.com');
    expect(request.password, 'fake-password');
    expect(viewModel.state, isA<RegisterSucceeded>());
  });

  for (final (label, values) in <(String, void Function())>[
    ('an empty name', () => fill(name: '')),
    ('a name over 80 characters', () => fill(name: 'a' * 81)),
    ('a non-ASCII email', () => fill(email: 'josé@example.com')),
    ('a short password', () => fill(password: 'short')),
    ('a password over 72 bytes', () => fill(password: 'é' * 37)),
  ]) {
    test('$label blocks the submit', () async {
      values();

      await controller.onSubmit();

      expect(auth.registers, isEmpty);
      expect(viewModel.state, isA<RegisterIdle>());
    });
  }

  test('editing a field clears a failure', () async {
    auth.failure = const NetworkFailure();
    fill();
    await controller.onSubmit();

    controller.onFieldEdited();

    expect(viewModel.state, isA<RegisterIdle>());
  });

  test('uses the register rules: the password has a minimum', () {
    expect(controller.passwordError('a'), AuthFieldError.passwordTooShort);
    expect(controller.nameError('Ana\nSouza'), AuthFieldError.nameInvalidChars);
  });

  test('the password starts hidden and toggles', () {
    expect(controller.passwordVisible.value, isFalse);

    controller.togglePasswordVisibility();

    expect(controller.passwordVisible.value, isTrue);
  });

  test('"I already have an account" is a navigation intent to login', () {
    controller.onLoginTapped();

    expect(navigator.wentTo, [AppRoute.login]);
  });

  test('never navigates on success: the router redirect does', () async {
    fill();

    await controller.onSubmit();

    expect(navigator.wentTo, isEmpty);
    expect(navigator.pushed, isEmpty);
  });

  test('dispose releases the text fields, focus nodes and the visibility notifier', () {
    final local = RegisterController(viewModel: viewModel, navigator: navigator)..dispose();

    for (final notifier in <ChangeNotifier>[
      local.nameField,
      local.emailField,
      local.passwordField,
      local.nameFocus,
      local.emailFocus,
      local.passwordFocus,
      local.passwordVisible,
    ]) {
      expect(() => notifier.addListener(() {}), throwsFlutterError);
    }
  });
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/api/api_stack.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/email_verification_repository.dart';
import 'package:snapledger/features/auth/login/application/controller/login_controller.dart';
import 'package:snapledger/features/auth/login/application/viewmodel/login_view_model.dart';
import 'package:snapledger/features/auth/password_reset/application/controller/password_reset_controller.dart';
import 'package:snapledger/features/auth/password_reset/application/viewmodel/password_reset_view_model.dart';
import 'package:snapledger/features/auth/register/application/controller/register_controller.dart';
import 'package:snapledger/features/auth/register/application/viewmodel/register_view_model.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/fake_navigator.dart';
import '../../support/fake_session_refresher.dart';
import '../../support/json_fixtures.dart';

const _password = 'fake-password-never-printed';
const _code = '042917';
const _newPassword = 'fake-new-password-never-printed';
const _resetToken = 'fake-reset-token-never-printed';
const _secrets = [_password, _newPassword, _code, _resetToken,'fake-access-1', 'fake-refresh-1', 'ana@example.com', 'Ana Souza'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> printed;
  late SessionNotifier session;

  setUp(() {
    printed = [];
    session = inMemorySession().session;
  });

  tearDown(() => session.dispose());

  // The real repository and ApiClient over a fake network, so every layer's output is captured.
  // PT: O repositório e o ApiClient reais sobre uma rede falsa, para capturar a saída de toda camada.
  AuthRepository repositoryAnswering(ResponseBody Function() answer) {
    final config = AppConfig.parse('https://api.test', isRelease: true);
    final adapter = FakeHttpAdapter((_) async => answer());
    return ApiAuthRepository(ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = adapter));
  }

  Future<void> capturingPrints(Future<void> Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(print: (_, _, _, line) => printed.add(line)),
  );

  void expectNoSecretIn(Iterable<String> texts) {
    for (final text in texts) {
      for (final secret in _secrets) {
        expect(text, isNot(contains(secret)), reason: 'printed or described: $text');
      }
    }
  }

  for (final (label, answer, succeeds) in [
    ('success', () => jsonBody(200, fakeAuthJson(1)), true),
    ('invalid credentials', () => problemBody(401, 'invalid-credentials'), false),
    ('validation error', () => validationProblemBody(['email', 'password']), false),
  ]) {
    test('login ($label) prints nothing sensitive and its state hides it', () async {
      final pending = PendingVerification(session: session);
      addTearDown(pending.dispose);
      final viewModel = LoginViewModel(
        auth: repositoryAnswering(answer),
        session: session,
        pending: pending,
      );
      final controller = LoginController(viewModel: viewModel, navigator: FakeNavigator())
        ..emailField.text = 'ana@example.com'
        ..passwordField.text = _password;

      await capturingPrints(controller.onSubmit);

      final state = viewModel.state;
      expect(state, succeeds ? isA<LoginSucceeded>() : isA<LoginFailed>());
      expectNoSecretIn([...printed, '$state', if (state is LoginFailed) '${state.failure}']);
      controller.dispose();
      viewModel.dispose();
    });
  }

  for (final (label, answer, succeeds) in [
    ('success', () => jsonBody(201, fakeAuthJson(1)), true),
    ('email taken', () => problemBody(409, 'email-already-registered'), false),
  ]) {
    test('register ($label) prints nothing sensitive and its state hides it', () async {
      final pending = PendingVerification(session: session);
      addTearDown(pending.dispose);
      final viewModel = RegisterViewModel(
        auth: repositoryAnswering(answer),
        session: session,
        pending: pending,
      );
      final controller = RegisterController(viewModel: viewModel, navigator: FakeNavigator())
        ..nameField.text = 'Ana Souza'
        ..emailField.text = 'ana@example.com'
        ..passwordField.text = _password;

      await capturingPrints(controller.onSubmit);

      final state = viewModel.state;
      expect(state, succeeds ? isA<RegisterSucceeded>() : isA<RegisterFailed>());
      expectNoSecretIn([...printed, '$state', if (state is RegisterFailed) '${state.failure}']);
      controller.dispose();
      viewModel.dispose();
    });
  }

  // The three requests of the flow: code request (202), verify (the reset token comes back), confirm.
  // PT: As três requisições do fluxo: pedir código (202), verificar (volta o reset token), confirmar.
  for (final (label, verifyAnswer, confirmAnswer) in [
    (
      'success',
      () => jsonBody(200, {'resetToken': _resetToken, 'expiresIn': 600}),
      () => textBody(204, ''),
    ),
    ('invalid code', () => problemBody(400, 'invalid-code'), () => textBody(204, '')),
    (
      'invalid reset token',
      () => jsonBody(200, {'resetToken': _resetToken, 'expiresIn': 600}),
      () => problemBody(400, 'invalid-reset-token'),
    ),
    ('too many requests', () => problemBody(429, 'too-many-requests'), () => textBody(204, '')),
  ]) {
    test('password reset ($label) prints nothing sensitive and its state hides it', () async {
      var call = 0;
      final repository = repositoryAnswering(() {
        call++;
        return switch (call) {
          1 => textBody(202, ''),
          2 => verifyAnswer(),
          _ => confirmAnswer(),
        };
      });
      final viewModel = PasswordResetViewModel(auth: repository, successPause: Duration.zero);
      final controller = PasswordResetController(viewModel: viewModel, navigator: FakeNavigator())
        ..emailField.text = 'ana@example.com'
        ..newPasswordField.text = _newPassword;
      final states = <String>[];
      viewModel.addListener(() => states.add('${viewModel.state}'));

      await capturingPrints(() async {
        await controller.onSubmitEmail();
        await controller.onCodeCompleted(_code);
        await controller.onSubmitNewPassword();
      });

      expectNoSecretIn([...printed, ...states, '${viewModel.state}']);
      controller.dispose();
      viewModel.dispose();
    });
  }

  test('email verification prints nothing sensitive and its failure hides it', () async {
    final adapter = FakeHttpAdapter((_) async => problemBody(400, 'invalid-code'));
    final config = AppConfig.parse('https://api.test', isRelease: true);
    final repository = ApiEmailVerificationRepository(
      ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = adapter),
    );
    Object? failure;

    await capturingPrints(() async {
      try {
        await repository.confirm(_code);
      } on ApiFailure catch (error) {
        failure = error;
      }
    });

    expect(failure, isA<ProblemFailure>());
    expectNoSecretIn([...printed, '$failure']);
  });
}

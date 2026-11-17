import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_stack.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/auth/login/application/controller/login_controller.dart';
import 'package:snapledger/features/auth/login/application/viewmodel/login_view_model.dart';
import 'package:snapledger/features/auth/register/application/controller/register_controller.dart';
import 'package:snapledger/features/auth/register/application/viewmodel/register_view_model.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/fake_navigator.dart';
import '../../support/fake_session_refresher.dart';
import '../../support/json_fixtures.dart';

const _password = 'fake-password-never-printed';
const _secrets = [_password, 'fake-access-1', 'fake-refresh-1', 'ana@example.com', 'Ana Souza'];

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
      final viewModel = LoginViewModel(auth: repositoryAnswering(answer), session: session);
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
      final viewModel = RegisterViewModel(auth: repositoryAnswering(answer), session: session);
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
}

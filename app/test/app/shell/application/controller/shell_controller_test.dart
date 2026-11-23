import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/app/shell/application/controller/shell_controller.dart';
import 'package:snapledger/app/shell/application/viewmodel/shell_view_model.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/session/session_notifier.dart';

import '../../../../support/fake_auth_repository.dart';
import '../../../../support/fake_navigator.dart';
import '../../../../support/fake_session_refresher.dart';

void main() {
  late FakeNavigator navigator;
  late FakeAuthRepository auth;
  late ShellViewModel viewModel;
  late ShellController controller;
  late SessionNotifier session;

  setUp(() {
    navigator = FakeNavigator();
    auth = FakeAuthRepository();
    session = inMemorySession().session;
    viewModel = ShellViewModel(auth: auth, session: session);
    controller = ShellController(viewModel: viewModel, navigator: navigator);
  });

  tearDown(() {
    viewModel.dispose();
    session.dispose();
  });

  test('onProfileTapped goes to the profile', () {
    controller.onProfileTapped();

    expect(navigator.wentTo, [AppRoute.profile]);
  });

  test('onCategoriesTapped pushes the categories', () {
    controller.onCategoriesTapped();

    expect(navigator.pushed, [AppRoute.categories]);
  });

  test('onLogoutTapped starts the sign out', () async {
    controller.onLogoutTapped();

    expect(viewModel.loggingOut, isTrue);
    await Future<void>.delayed(Duration.zero);
  });
}

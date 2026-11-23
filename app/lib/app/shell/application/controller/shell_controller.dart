import 'dart:async';

import 'package:snapledger/app/shell/application/viewmodel/shell_view_model.dart';
import 'package:snapledger/core/router/app_navigator.dart';

/// User events of the top bar and its account menu; tab switching stays with the shell's `goBranch`.
/// PT: Eventos do usuário na barra superior e no menu da conta; trocar de aba fica com o `goBranch` da moldura.
/// Notes: docs/code-notes/app-core.md#responsive-shell
class ShellController {
  ShellController({required this._viewModel, required this._navigator});

  final ShellViewModel _viewModel;
  final AppNavigator _navigator;

  void onProfileTapped() => _navigator.goTo(AppRoute.profile);

  void onCategoriesTapped() => unawaited(_navigator.push(AppRoute.categories));

  void onLogoutTapped() => unawaited(_viewModel.logout());
}

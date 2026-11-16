import 'dart:async';

import 'package:snapledger/features/profile/overview/application/viewmodel/profile_view_model.dart';

/// User events of the profile screen; signing out navigates through the session, not from here.
/// PT: Eventos do usuário no perfil; sair navega pela sessão, não por aqui.
/// Notes: docs/code-notes/app-profile.md#profileviewmodel
class ProfileController {
  ProfileController({required this._viewModel});

  final ProfileViewModel _viewModel;

  void start() => unawaited(_viewModel.load());

  void onRetryTapped() => unawaited(_viewModel.load());

  void onLogoutTapped() => unawaited(_viewModel.logout());
}

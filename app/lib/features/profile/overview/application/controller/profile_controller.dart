import 'dart:async';

import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/profile/overview/application/viewmodel/profile_view_model.dart';

/// User events of the profile screen; signing out navigates through the session, not from here.
/// PT: Eventos do usuário no perfil; sair navega pela sessão, não por aqui.
/// Notes: docs/code-notes/app-profile.md#profileviewmodel
class ProfileController {
  ProfileController({required this._viewModel, required this._navigator});

  final ProfileViewModel _viewModel;
  final AppNavigator _navigator;

  void start() => unawaited(_viewModel.load());

  void onRetryTapped() => unawaited(_viewModel.load());

  void onLogoutTapped() => unawaited(_viewModel.logout());

  /// Opens the Verify email screen and reloads the profile when it closes, so the banner reflects the result.
  /// PT: Abre a tela de verificar email e recarrega o perfil quando ela fecha, para o banner refletir o resultado.
  /// Notes: docs/code-notes/app-profile.md#verify-email-banner
  Future<void> onVerifyEmailTapped() async {
    await _navigator.push(AppRoute.verifyEmail);
    await _viewModel.load();
  }
}

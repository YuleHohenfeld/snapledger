import 'dart:async';

import 'package:snapledger/features/auth/splash/application/viewmodel/splash_view_model.dart';

/// User events of the splash screen; it holds no screen state and never navigates (the redirect does).
/// PT: Eventos do usuário no splash; não guarda estado de tela e nunca navega (o redirect navega).
/// Notes: docs/code-notes/app-auth.md#splashviewmodel
class SplashController {
  SplashController({required this._viewModel});

  final SplashViewModel _viewModel;

  void start() => unawaited(_viewModel.start());

  void onRetryTapped() => unawaited(_viewModel.retry());

  void onSignInAgainTapped() => unawaited(_viewModel.signInAgain());
}

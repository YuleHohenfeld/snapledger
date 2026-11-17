import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/features/auth/splash/application/controller/splash_controller.dart';
import 'package:snapledger/features/auth/splash/application/viewmodel/splash_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The first screen: a spinner while the stored session is checked, retry options if it cannot be.
/// PT: A primeira tela: um spinner enquanto a sessão guardada é verificada, opções de repetir se não der.
/// Notes: docs/code-notes/app-auth.md#splashviewmodel
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) => SplashViewModel(session: context.read()),
    child: const _SplashView(),
  );
}

class _SplashView extends StatefulWidget {
  const _SplashView();

  @override
  State<_SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<_SplashView> {
  late final SplashController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SplashController(viewModel: context.read<SplashViewModel>())..start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final failed = context.select((SplashViewModel vm) => vm.state is SplashRestoreFailed);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: failed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.splashRetryMessage, textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.l),
                      FilledButton(
                        onPressed: _controller.onRetryTapped,
                        child: Text(l10n.splashRetry),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      TextButton(
                        onPressed: _controller.onSignInAgainTapped,
                        child: Text(l10n.splashSignInAgain),
                      ),
                    ],
                  )
                : Semantics(
                    label: l10n.splashLoadingSemantics,
                    child: const CircularProgressIndicator(),
                  ),
          ),
        ),
      ),
    );
  }
}

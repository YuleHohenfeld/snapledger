import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/auth_scaffold.dart';
import 'package:snapledger/core/design/widgets/brand_header.dart';
import 'package:snapledger/core/design/widgets/prompt_link_row.dart';
import 'package:snapledger/features/auth/login/application/controller/login_controller.dart';
import 'package:snapledger/features/auth/login/application/viewmodel/login_view_model.dart';
import 'package:snapledger/features/auth/login/presentation/widgets/login_form.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The login screen: owns its ViewModel (disposed with the screen) and its Controller.
/// PT: A tela de login: é dona do seu ViewModel (descartado com a tela) e do seu Controller.
/// Notes: docs/code-notes/app-auth.md#pages
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  // Dependencies are inferred from the constructor's types, so the View never imports the repository.
  // PT: As dependências são inferidas pelos tipos do construtor, então a View nunca importa o repositório.
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) =>
        LoginViewModel(auth: context.read(), session: context.read(), pending: context.read()),
    child: const _LoginView(),
  );
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  late final LoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LoginController(
      viewModel: context.read<LoginViewModel>(),
      navigator: context.read(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthScaffold(
      footer: PromptLinkRow(
        prompt: l10n.loginNoAccount,
        actionLabel: l10n.loginCreateAccount,
        onPressed: _controller.onCreateAccountTapped,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.l),
          const BrandHeader(),
          const SizedBox(height: AppSpacing.xl),
          LoginForm(controller: _controller),
        ],
      ),
    );
  }
}

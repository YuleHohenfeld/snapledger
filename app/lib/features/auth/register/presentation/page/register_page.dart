import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/widgets/auth_scaffold.dart';
import 'package:snapledger/core/design/widgets/prompt_link_row.dart';
import 'package:snapledger/features/auth/register/application/controller/register_controller.dart';
import 'package:snapledger/features/auth/register/application/viewmodel/register_view_model.dart';
import 'package:snapledger/features/auth/register/presentation/widgets/register_form.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The register screen: owns its ViewModel (disposed with the screen) and its Controller.
/// PT: A tela de cadastro: é dona do seu ViewModel (descartado com a tela) e do seu Controller.
/// Notes: docs/code-notes/app-auth.md#pages
class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  // Dependencies are inferred from the constructor's types, so the View never imports the repository.
  // PT: As dependências são inferidas pelos tipos do construtor, então a View nunca importa o repositório.
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) =>
        RegisterViewModel(auth: context.read(), session: context.read(), pending: context.read()),
    child: const _RegisterView(),
  );
}

class _RegisterView extends StatefulWidget {
  const _RegisterView();

  @override
  State<_RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<_RegisterView> {
  late final RegisterController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RegisterController(
      viewModel: context.read<RegisterViewModel>(),
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
      onBack: _controller.onLoginTapped,
      footer: PromptLinkRow(
        prompt: l10n.registerHaveAccountPrompt,
        actionLabel: l10n.registerHaveAccount,
        onPressed: _controller.onLoginTapped,
      ),
      child: RegisterForm(controller: _controller),
    );
  }
}

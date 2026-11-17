import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/brand_header.dart';
import 'package:snapledger/core/design/widgets/centered_form_scaffold.dart';
import 'package:snapledger/features/auth/register/application/controller/register_controller.dart';
import 'package:snapledger/features/auth/register/application/viewmodel/register_view_model.dart';
import 'package:snapledger/features/auth/register/presentation/widgets/register_form.dart';

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
  Widget build(BuildContext context) => CenteredFormScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BrandHeader(),
        const SizedBox(height: AppSpacing.xl),
        RegisterForm(controller: _controller),
      ],
    ),
  );
}

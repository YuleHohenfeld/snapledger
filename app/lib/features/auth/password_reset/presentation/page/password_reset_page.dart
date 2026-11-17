import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/widgets/auth_scaffold.dart';
import 'package:snapledger/features/auth/password_reset/application/controller/password_reset_controller.dart';
import 'package:snapledger/features/auth/password_reset/application/viewmodel/password_reset_view_model.dart';
import 'package:snapledger/features/auth/password_reset/presentation/widgets/password_reset_code_step.dart';
import 'package:snapledger/features/auth/password_reset/presentation/widgets/password_reset_done_step.dart';
import 'package:snapledger/features/auth/password_reset/presentation/widgets/password_reset_email_step.dart';
import 'package:snapledger/features/auth/password_reset/presentation/widgets/password_reset_new_password_step.dart';

/// The password reset flow: one route, four steps (email, code, new password, done); nothing sensitive in the URL.
/// PT: O fluxo de troca de senha: uma rota, quatro passos (email, código, nova senha, concluído); nada sensível na URL.
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
class PasswordResetPage extends StatelessWidget {
  const PasswordResetPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) => PasswordResetViewModel(auth: context.read()),
    child: const _PasswordResetView(),
  );
}

class _PasswordResetView extends StatefulWidget {
  const _PasswordResetView();

  @override
  State<_PasswordResetView> createState() => _PasswordResetViewState();
}

class _PasswordResetViewState extends State<_PasswordResetView> {
  late final PasswordResetController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PasswordResetController(
      viewModel: context.read<PasswordResetViewModel>(),
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
    final state = context.select((PasswordResetViewModel vm) => vm.state);
    return AuthScaffold(
      // The last screen has no way back: the only exit is "Back to sign in".
      // PT: A última tela não tem como voltar: a única saída é "Voltar ao login".
      onBack: state is PasswordResetDone ? null : _controller.onBack,
      child: switch (state) {
        PasswordResetEnterEmail() => PasswordResetEmailStep(controller: _controller),
        PasswordResetEnterCode() => PasswordResetCodeStep(controller: _controller),
        PasswordResetNewPassword() => PasswordResetNewPasswordStep(controller: _controller),
        PasswordResetDone() => PasswordResetDoneStep(controller: _controller),
      },
    );
  }
}

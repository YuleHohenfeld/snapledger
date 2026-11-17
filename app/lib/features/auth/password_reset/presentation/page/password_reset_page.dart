import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/brand_header.dart';
import 'package:snapledger/core/design/widgets/centered_form_scaffold.dart';
import 'package:snapledger/features/auth/password_reset/application/controller/password_reset_controller.dart';
import 'package:snapledger/features/auth/password_reset/application/viewmodel/password_reset_view_model.dart';
import 'package:snapledger/features/auth/password_reset/presentation/widgets/password_reset_code_step.dart';
import 'package:snapledger/features/auth/password_reset/presentation/widgets/password_reset_done_step.dart';
import 'package:snapledger/features/auth/password_reset/presentation/widgets/password_reset_email_step.dart';

/// The password reset screen: one page, three steps (email, code and new password, done).
/// PT: A tela de troca de senha: uma página, três passos (email, código e nova senha, concluído).
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
    return CenteredFormScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandHeader(),
          const SizedBox(height: AppSpacing.xl),
          switch (state) {
            PasswordResetEnterEmail() => PasswordResetEmailStep(controller: _controller),
            PasswordResetEnterCode() => PasswordResetCodeStep(controller: _controller),
            PasswordResetDone() => PasswordResetDoneStep(controller: _controller),
          },
        ],
      ),
    );
  }
}

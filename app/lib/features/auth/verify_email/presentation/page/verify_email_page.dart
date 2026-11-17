import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/brand_header.dart';
import 'package:snapledger/core/design/widgets/centered_form_scaffold.dart';
import 'package:snapledger/features/auth/verify_email/application/controller/verify_email_controller.dart';
import 'package:snapledger/features/auth/verify_email/application/viewmodel/verify_email_view_model.dart';
import 'package:snapledger/features/auth/verify_email/presentation/widgets/verify_email_form.dart';

/// The Verify email screen, shown right after register and from the profile banner.
/// PT: A tela de verificar email, mostrada logo após o cadastro e pelo banner do perfil.
/// Notes: docs/code-notes/app-auth.md#verifyemailviewmodel
class VerifyEmailPage extends StatelessWidget {
  const VerifyEmailPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) => VerifyEmailViewModel(
      users: context.read(),
      verification: context.read(),
      pending: context.read(),
    ),
    child: const _VerifyEmailView(),
  );
}

class _VerifyEmailView extends StatefulWidget {
  const _VerifyEmailView();

  @override
  State<_VerifyEmailView> createState() => _VerifyEmailViewState();
}

class _VerifyEmailViewState extends State<_VerifyEmailView> {
  late final VerifyEmailController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VerifyEmailController(
      viewModel: context.read<VerifyEmailViewModel>(),
      navigator: context.read(),
    )..start();
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
        VerifyEmailForm(controller: _controller),
      ],
    ),
  );
}

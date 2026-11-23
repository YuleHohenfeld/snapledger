import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/profile/overview/application/controller/profile_controller.dart';
import 'package:snapledger/features/profile/overview/application/viewmodel/profile_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The profile tab: name, email and currency of the signed-in user, and sign out.
/// PT: A aba de perfil: nome, email e moeda do usuário logado, e o botão de sair.
/// Notes: docs/code-notes/app-profile.md#profileviewmodel
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) =>
        ProfileViewModel(users: context.read(), auth: context.read(), session: context.read()),
    child: const _ProfileView(),
  );
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  late final ProfileController _controller;

  static const _maxWidth = 420.0;

  @override
  void initState() {
    super.initState();
    _controller = ProfileController(
      viewModel: context.read<ProfileViewModel>(),
      navigator: context.read(),
    )..start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.select((ProfileViewModel vm) => vm.state);
    final loggingOut = context.select((ProfileViewModel vm) => vm.loggingOut);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  switch (state) {
                    ProfileLoading() => const Center(child: CircularProgressIndicator()),
                    ProfileLoaded(:final user) => Column(
                      children: [
                        if (!user.emailVerified) ...[
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.mark_email_unread_outlined),
                              title: Text(l10n.profileVerifyEmailBanner),
                              trailing: TextButton(
                                onPressed: _controller.onVerifyEmailTapped,
                                child: Text(l10n.profileVerifyEmailAction),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s),
                        ],
                        ListTile(title: Text(l10n.profileNameLabel), subtitle: Text(user.name)),
                        ListTile(title: Text(l10n.profileEmailLabel), subtitle: Text(user.email)),
                        ListTile(
                          title: Text(l10n.profileCurrencyLabel),
                          subtitle: Text(user.currency),
                        ),
                      ],
                    ),
                    ProfileFailed(:final failure) => Column(
                      children: [
                        Text(failureMessage(l10n, failure) ?? l10n.errorUnexpected),
                        const SizedBox(height: AppSpacing.m),
                        OutlinedButton(
                          onPressed: _controller.onRetryTapped,
                          child: Text(l10n.profileRetry),
                        ),
                      ],
                    ),
                  },
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: Text(l10n.profileCategoriesRow),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _controller.onCategoriesTapped,
                  ),
                  const SizedBox(height: AppSpacing.l),
                  FilledButton(
                    onPressed: loggingOut ? null : _controller.onLogoutTapped,
                    child: loggingOut
                        ? Semantics(
                            label: l10n.profileLoggingOut,
                            child: const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Text(l10n.profileLogout),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

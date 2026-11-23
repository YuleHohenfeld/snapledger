import 'package:flutter/material.dart';
import 'package:snapledger/app/shell/application/controller/shell_controller.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

enum _AccountAction { profile, categories, logout }

/// The account button of the top bar and its menu: Profile, Categories and Sign out.
/// PT: O botão de conta da barra superior e o menu dele: Perfil, Categorias e Sair.
/// Notes: docs/code-notes/app-core.md#responsive-shell
class ShellAccountMenu extends StatelessWidget {
  const ShellAccountMenu({required this.controller, required this.loggingOut, super.key});

  final ShellController controller;

  /// While signing out the item is disabled, so it cannot be chosen twice.
  /// PT: Durante o logout o item fica desativado, para não ser escolhido duas vezes.
  final bool loggingOut;

  static const _iconSize = 30.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_AccountAction>(
      tooltip: l10n.shellAccountMenuTooltip,
      icon: const Icon(Icons.account_circle_outlined),
      iconSize: _iconSize,
      onSelected: (action) => switch (action) {
        _AccountAction.profile => controller.onProfileTapped(),
        _AccountAction.categories => controller.onCategoriesTapped(),
        _AccountAction.logout => controller.onLogoutTapped(),
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _AccountAction.profile,
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(l10n.navProfile),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _AccountAction.categories,
          child: ListTile(
            leading: const Icon(Icons.category_outlined),
            title: Text(l10n.profileCategoriesRow),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _AccountAction.logout,
          enabled: !loggingOut,
          child: ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l10n.profileLogout),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:snapledger/app/shell/application/controller/shell_controller.dart';
import 'package:snapledger/app/shell/presentation/widgets/shell_account_menu.dart';
import 'package:snapledger/app/shell/presentation/widgets/shell_top_tab.dart';
import 'package:snapledger/core/design/app_colors.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/glass_panel.dart';
import 'package:snapledger/core/design/widgets/gradient_text.dart';
import 'package:snapledger/core/design/widgets/responsive_body.dart';
import 'package:snapledger/core/design/window_size.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The top bar of expanded windows: brand, the Summary and Expenses tabs and the account menu.
/// PT: A barra superior das janelas expandidas: marca, as abas Resumo e Despesas e o menu da conta.
/// It is a plain widget placed above the body (not the `Scaffold.appBar` slot, whose height is fixed): it is
/// [contentHeight] tall plus the top inset of the screen, so a notch never squeezes the content.
/// PT: É um widget comum acima do corpo (não o slot `Scaffold.appBar`, de altura fixa): tem [contentHeight] mais o
/// recuo superior da tela, então um notch nunca espreme o conteúdo.
/// Notes: docs/code-notes/app-core.md#responsive-shell
class ShellTopBar extends StatelessWidget {
  const ShellTopBar({
    required this.selectedIndex,
    required this.onTabSelected,
    required this.controller,
    required this.loggingOut,
    super.key,
  });

  /// The current branch of the shell; the Profile branch (2) highlights no top tab.
  /// PT: O branch atual da moldura; o branch Perfil (2) não destaca nenhuma aba.
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final ShellController controller;
  final bool loggingOut;

  /// Height of the bar below the top inset.
  /// PT: Altura da barra abaixo do recuo superior.
  static const contentHeight = 64.0;
  static const _markSize = 32.0;
  static const _markIconSize = 18.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gradients = BrandGradients.of(context);
    return GlassBar(
      edge: GlassEdge.bottom,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: contentHeight,
            child: ResponsiveBody(
              maxWidth: AppBreakpoints.dashboardWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: gradients.accentGradient,
                          borderRadius: BorderRadius.circular(AppGlass.markRadius),
                          boxShadow: [
                            BoxShadow(
                              color: gradients.glowColor.withValues(alpha: AppGlass.glowAlpha),
                              blurRadius: AppGlass.glowBlur / 2,
                            ),
                          ],
                        ),
                        child: SizedBox.square(
                          dimension: _markSize,
                          child: Icon(
                            Icons.receipt_long,
                            size: _markIconSize,
                            color: gradients.onHero,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    GradientText(
                      AppBrand.name,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: AppSpacing.l),
                    ShellTopTab(
                      label: l10n.navSummary,
                      selected: selectedIndex == 0,
                      onPressed: () => onTabSelected(0),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    ShellTopTab(
                      label: l10n.navExpenses,
                      selected: selectedIndex == 1,
                      onPressed: () => onTabSelected(1),
                    ),
                    const Spacer(),
                    ShellAccountMenu(controller: controller, loggingOut: loggingOut),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

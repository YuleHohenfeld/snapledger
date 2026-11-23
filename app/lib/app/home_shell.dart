import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/app/shell/application/controller/shell_controller.dart';
import 'package:snapledger/app/shell/application/viewmodel/shell_view_model.dart';
import 'package:snapledger/app/shell/presentation/widgets/shell_top_bar.dart';
import 'package:snapledger/core/design/widgets/app_backdrop.dart';
import 'package:snapledger/core/design/widgets/glass_panel.dart';
import 'package:snapledger/core/design/window_size.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The signed-in frame, chosen by window width: a bottom bar (compact), a navigation rail (medium) or a
/// top bar (expanded), around the current tab.
/// PT: A moldura da área logada, escolhida pela largura da janela: barra inferior (compact), navigation rail
/// (medium) ou barra superior (expanded), em volta da aba atual.
/// Notes: docs/code-notes/app-core.md#responsive-shell
class HomeShell extends StatelessWidget {
  const HomeShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) => ShellViewModel(auth: context.read(), session: context.read()),
    child: _ShellView(shell: shell),
  );
}

class _ShellView extends StatefulWidget {
  const _ShellView({required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<_ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<_ShellView> {
  late final ShellController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ShellController(
      viewModel: context.read<ShellViewModel>(),
      navigator: context.read(),
    );
  }

  // Named exception to "the View never navigates": `goBranch` lives on the shell object, which exists only in
  // app/, so `AppNavigator` cannot own it. Tapping the current tab goes back to its first screen.
  // PT: Exceção nomeada a "a View nunca navega": `goBranch` vive no objeto da moldura, que só existe em app/,
  // então o `AppNavigator` não pode tê-lo. Tocar na aba atual volta à primeira tela dela.
  // Notes: docs/code-notes/app-core.md#responsive-shell
  void _onTabSelected(int index) =>
      widget.shell.goBranch(index, initialLocation: index == widget.shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shell = widget.shell;
    final loggingOut = context.select((ShellViewModel vm) => vm.loggingOut);
    final Widget layout;
    switch (WindowSize.of(context)) {
      case WindowSize.expanded:
        // The bar sits above the body (not in `appBar`) so it can be taller by the top inset; the body then
        // drops that inset, because the bar already used it.
        // PT: A barra fica acima do corpo (não em `appBar`) para poder ser mais alta pelo recuo superior; o
        // corpo então descarta esse recuo, porque a barra já o usou.
        layout = Scaffold(
          body: Column(
            children: [
              ShellTopBar(
                selectedIndex: shell.currentIndex,
                onTabSelected: _onTabSelected,
                controller: _controller,
                loggingOut: loggingOut,
              ),
              Expanded(
                child: MediaQuery.removePadding(context: context, removeTop: true, child: shell),
              ),
            ],
          ),
        );
      case WindowSize.medium:
        layout = Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassBar(
                edge: GlassEdge.end,
                child: NavigationRail(
                  selectedIndex: shell.currentIndex,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: _onTabSelected,
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(Icons.pie_chart_outline),
                      label: Text(l10n.navSummary),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: Text(l10n.navExpenses),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.person_outline),
                      label: Text(l10n.navProfile),
                    ),
                  ],
                ),
              ),
              Expanded(child: shell),
            ],
          ),
        );
      case WindowSize.compact:
        layout = Scaffold(
          body: shell,
          bottomNavigationBar: GlassBar(
            edge: GlassEdge.top,
            child: NavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _onTabSelected,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.pie_chart_outline),
                  label: l10n.navSummary,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: l10n.navExpenses,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person_outline),
                  label: l10n.navProfile,
                ),
              ],
            ),
          ),
        );
    }
    return AppBackdrop(child: layout);
  }
}

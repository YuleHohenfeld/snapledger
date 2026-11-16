import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The signed-in frame: the current tab above a bottom bar with Summary, Expenses and Profile.
/// PT: A moldura da área logada: a aba atual sobre uma barra inferior com Resumo, Despesas e Perfil.
/// Notes: docs/code-notes/app-core.md#composition-root
class HomeShell extends StatelessWidget {
  const HomeShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        // Tapping the current tab goes back to its first screen.
        // PT: Tocar na aba atual volta à primeira tela dela.
        onDestinationSelected: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.pie_chart_outline), label: l10n.navSummary),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            label: l10n.navExpenses,
          ),
          NavigationDestination(icon: const Icon(Icons.person_outline), label: l10n.navProfile),
        ],
      ),
    );
  }
}

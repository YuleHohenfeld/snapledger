import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Shown instead of the app when API_BASE_URL is missing or unsafe, so it never calls a wrong server.
/// PT: Mostrado no lugar do app quando o API_BASE_URL falta ou é inseguro, para nunca chamar um servidor errado.
/// Notes: docs/code-notes/app-core.md#appconfig
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => AppBrand.name,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const _ConfigErrorScreen(),
  );
}

class _ConfigErrorScreen extends StatelessWidget {
  const _ConfigErrorScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.configErrorTitle, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.m),
                Text(l10n.configErrorBody, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

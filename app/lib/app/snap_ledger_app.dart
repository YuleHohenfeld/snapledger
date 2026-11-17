import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/app/app_providers.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/storage/secure_store.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The root widget: app-wide providers above a `MaterialApp.router`; [secureStore] is for tests.
/// PT: O widget raiz: providers do app inteiro acima de um `MaterialApp.router`; [secureStore] é para testes.
/// Notes: docs/code-notes/app-core.md#composition-root
class SnapLedgerApp extends StatelessWidget {
  const SnapLedgerApp(this.config, {super.key, this.secureStore});

  final AppConfig config;
  final SecureStore? secureStore;

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: buildAppProviders(config, secureStore: secureStore),
    child: const _RouterApp(),
  );
}

class _RouterApp extends StatelessWidget {
  const _RouterApp();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    onGenerateTitle: (context) => AppBrand.name,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: context.read<GoRouter>(),
  );
}

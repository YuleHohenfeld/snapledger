import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';

void main() {
  runApp(const SnapLedgerApp());
}

/// Placeholder root widget until the composition root (lib/app) adds the router, session and l10n.
/// PT: Widget raiz provisório até a composition root (lib/app) trazer o router, a sessão e o l10n.
class SnapLedgerApp extends StatelessWidget {
  const SnapLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBrand.name,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const Scaffold(body: Center(child: Text(AppBrand.name))),
    );
  }
}

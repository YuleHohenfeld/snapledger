import 'package:flutter/material.dart';

void main() {
  runApp(const SnapLedgerApp());
}

/// Placeholder root widget until the first feature adds the router, session and l10n.
/// PT: Widget raiz provisório até a primeira feature trazer o router, a sessão e o l10n.
class SnapLedgerApp extends StatelessWidget {
  const SnapLedgerApp({super.key});

  // The product name is a brand, not a translated string.
  // PT: O nome do produto é uma marca, não um texto traduzido.
  static const String productName = 'SnapLedger';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: productName,
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const Scaffold(body: Center(child: Text(productName))),
    );
  }
}

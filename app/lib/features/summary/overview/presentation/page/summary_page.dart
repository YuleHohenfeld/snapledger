import 'package:flutter/material.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Placeholder of the Summary tab until its feature is built.
/// PT: Marcador da aba Resumo até a feature ser construída.
class SummaryPage extends StatelessWidget {
  const SummaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.summaryTitle)),
      body: Center(child: Text(l10n.placeholderComingSoon)),
    );
  }
}

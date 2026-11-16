import 'package:flutter/widgets.dart';
import 'package:snapledger/app/config_error_app.dart';
import 'package:snapledger/app/snap_ledger_app.dart';
import 'package:snapledger/core/config/app_config.dart';

/// Reads the build configuration first: an invalid one shows an error screen, never a wrong server.
/// PT: Lê primeiro a configuração do build: uma inválida mostra uma tela de erro, nunca um servidor errado.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    runApp(SnapLedgerApp(AppConfig.fromEnvironment()));
  } on ConfigException {
    runApp(const ConfigErrorApp());
  }
}

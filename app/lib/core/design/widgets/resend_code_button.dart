import 'package:flutter/material.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// "Resend code", or "Resend in 0:42" (disabled) while [remainingSeconds] is above zero; it owns no timer.
/// PT: "Reenviar código", ou "Reenviar em 0:42" (desativado) enquanto [remainingSeconds] é maior que zero; não tem timer.
/// Notes: docs/code-notes/app-auth.md#resendcooldown
class ResendCodeButton extends StatelessWidget {
  const ResendCodeButton({
    required this.remainingSeconds,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  /// Seconds left of the cooldown, counted by the ViewModel.
  /// PT: Segundos que faltam da espera, contados pelo ViewModel.
  final int remainingSeconds;

  /// A resend is in flight.
  /// PT: Um reenvio está em andamento.
  final bool busy;
  final VoidCallback onPressed;

  static String _clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final waiting = remainingSeconds > 0;
    return TextButton(
      onPressed: waiting || busy ? null : onPressed,
      child: Text(waiting ? l10n.codeResendIn(_clock(remainingSeconds)) : l10n.codeResend),
    );
  }
}

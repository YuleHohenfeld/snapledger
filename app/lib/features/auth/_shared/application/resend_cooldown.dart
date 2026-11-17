import 'dart:async';

import 'package:flutter/foundation.dart';

/// Creates the one-second ticks; tests may pass their own.
/// PT: Cria os ticks de um segundo; os testes podem passar o seu.
typedef CooldownTicker = Timer Function(Duration period, void Function(Timer timer) onTick);

/// Counts down the seconds before "Resend code" works again; the ViewModel owns it and cancels it on dispose.
/// PT: Conta os segundos até o "Reenviar código" voltar a funcionar; o ViewModel é dono dele e o cancela no dispose.
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
class ResendCooldown {
  ResendCooldown({
    required this._onChanged,
    this.duration = const Duration(seconds: 60),
    this._ticker = Timer.periodic,
  });

  final VoidCallback _onChanged;
  final Duration duration;
  final CooldownTicker _ticker;
  Timer? _timer;
  int _remaining = 0;

  /// Whole seconds left; 0 means a resend is allowed.
  /// PT: Segundos inteiros restantes; 0 significa que reenviar é permitido.
  int get remaining => _remaining;

  /// Restarts the countdown from [duration].
  /// PT: Reinicia a contagem a partir de [duration].
  void start() {
    _timer?.cancel();
    _remaining = duration.inSeconds;
    _timer = _ticker(const Duration(seconds: 1), (timer) {
      _remaining--;
      if (_remaining <= 0) {
        _remaining = 0;
        timer.cancel();
        _timer = null;
      }
      _onChanged();
    });
    _onChanged();
  }

  /// Stops the timer and drops the wait, so no stale "resend in 0:42" survives.
  /// PT: Para o timer e zera a espera, para nenhum "reenviar em 0:42" velho sobreviver.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _remaining = 0;
  }
}

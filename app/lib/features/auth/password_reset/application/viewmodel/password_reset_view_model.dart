import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/auth/_shared/application/resend_cooldown.dart';
import 'package:snapledger/features/auth/_shared/data/models/password_reset_requests.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';

/// Which step of the password reset the user is on; the View draws it and never sees a message string.
/// PT: Em qual passo da troca de senha o usuário está; a View o desenha e nunca recebe uma string de mensagem.
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
@immutable
sealed class PasswordResetState {
  const PasswordResetState();
}

/// Step 1: asking for the code.
/// PT: Passo 1: pedir o código.
final class PasswordResetEnterEmail extends PasswordResetState {
  const PasswordResetEnterEmail({this.busy = false, this.failure});

  final bool busy;

  /// The [ApiFailure] to localize.
  /// PT: O [ApiFailure] a traduzir.
  final ApiFailure? failure;
}

/// Step 2: the code was (maybe) sent to [email]; the email lives only here, never in a URL.
/// PT: Passo 2: o código foi (talvez) enviado a [email]; o email vive só aqui, nunca numa URL.
final class PasswordResetEnterCode extends PasswordResetState {
  const PasswordResetEnterCode(this.email, {this.busy = false, this.failure});

  final String email;
  final bool busy;
  final ApiFailure? failure;
}

/// The password changed and every session was revoked by the server.
/// PT: A senha mudou e o servidor revogou todas as sessões.
final class PasswordResetDone extends PasswordResetState {
  const PasswordResetDone();
}

/// Business state of the password reset: request a code, confirm it with the new password, resend.
/// PT: Estado de negócio da troca de senha: pedir um código, confirmá-lo com a nova senha, reenviar.
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
class PasswordResetViewModel extends ChangeNotifier {
  PasswordResetViewModel({
    required this._auth,
    Duration cooldown = const Duration(seconds: 60),
    CooldownTicker ticker = Timer.periodic,
  }) {
    _cooldown = ResendCooldown(onChanged: _notify, duration: cooldown, ticker: ticker);
  }

  final AuthRepository _auth;
  late final ResendCooldown _cooldown;
  PasswordResetState _state = const PasswordResetEnterEmail();
  bool _disposed = false;

  PasswordResetState get state => _state;

  /// Seconds until a resend is allowed; 0 when it is.
  /// PT: Segundos até um reenvio ser permitido; 0 quando é.
  int get cooldownSeconds => _cooldown.remaining;

  /// Step 1. Any `202` advances (the answer never says whether the account exists); a failure stays.
  /// PT: Passo 1. Todo `202` avança (a resposta nunca diz se a conta existe); uma falha fica.
  /// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
  Future<void> requestCode(String email) async {
    if (_state case PasswordResetEnterEmail(busy: false)) {
      final trimmed = email.trim();
      _emit(const PasswordResetEnterEmail(busy: true));
      try {
        await _auth.requestPasswordReset(PasswordResetRequest(email: trimmed));
        _emit(PasswordResetEnterCode(trimmed));
        _startCooldown();
      } on ApiFailure catch (failure) {
        _emit(PasswordResetEnterEmail(failure: failure));
      }
    }
  }

  /// Step 2. `invalid-code` keeps the step with the failure; success ends the flow.
  /// PT: Passo 2. `invalid-code` mantém o passo com a falha; o sucesso encerra o fluxo.
  Future<void> confirm({required String code, required String newPassword}) async {
    if (_state case PasswordResetEnterCode(:final email, busy: false)) {
      _emit(PasswordResetEnterCode(email, busy: true));
      try {
        await _auth.confirmPasswordReset(
          PasswordResetConfirmRequest(email: email, code: code, newPassword: newPassword),
        );
        _cooldown.cancel();
        _emit(const PasswordResetDone());
      } on ApiFailure catch (failure) {
        _emit(PasswordResetEnterCode(email, failure: failure));
      }
    }
  }

  /// Back to step 1 to fix a wrong address; the pending cooldown no longer applies to the new email.
  /// PT: Volta ao passo 1 para corrigir um endereço errado; a espera pendente não vale para o novo email.
  /// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
  void backToEmail() {
    if (_state case PasswordResetEnterCode(busy: false)) {
      _cooldown.cancel();
      _emit(const PasswordResetEnterEmail());
    }
  }

  /// Asks for a new code; ignored during the cooldown or while busy.
  /// PT: Pede um novo código; ignorado durante a espera ou ocupado.
  Future<void> resend() async {
    if (_state case PasswordResetEnterCode(:final email, busy: false) when _cooldown.remaining == 0) {
      _emit(PasswordResetEnterCode(email, busy: true));
      try {
        await _auth.requestPasswordReset(PasswordResetRequest(email: email));
        _emit(PasswordResetEnterCode(email));
      } on ApiFailure catch (failure) {
        _emit(PasswordResetEnterCode(email, failure: failure));
      }
      // Even a refused resend waits: hammering the button gains nothing.
      // PT: Mesmo um reenvio recusado espera: martelar o botão não adianta.
      _startCooldown();
    }
  }

  /// Drops a stale error once the user edits a field.
  /// PT: Descarta um erro antigo quando o usuário edita um campo.
  void clearFailure() {
    switch (_state) {
      case PasswordResetEnterEmail(failure: != null):
        _emit(const PasswordResetEnterEmail());
      case PasswordResetEnterCode(:final email, failure: != null):
        _emit(PasswordResetEnterCode(email));
      default:
    }
  }

  // An answer that arrives after the screen closed must not notify a disposed notifier.
  // PT: Uma resposta que chega depois que a tela fechou não pode notificar um notifier descartado.
  void _emit(PasswordResetState next) {
    _state = next;
    _notify();
  }

  // No timer may start after dispose: nothing would cancel it.
  // PT: Nenhum timer pode começar após o dispose: nada o cancelaria.
  void _startCooldown() {
    if (!_disposed) _cooldown.start();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cooldown.cancel();
    super.dispose();
  }
}

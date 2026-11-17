import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/auth/_shared/application/code_entry_status.dart';
import 'package:snapledger/features/auth/_shared/application/resend_cooldown.dart';
import 'package:snapledger/features/auth/_shared/data/models/password_reset_requests.dart';
import 'package:snapledger/features/auth/_shared/data/models/reset_grant.dart';
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
  const PasswordResetEnterCode(
    this.email, {
    this.status = CodeEntryStatus.idle,
    this.resending = false,
    this.failure,
  });

  final String email;
  final CodeEntryStatus status;

  /// A resend is in flight.
  /// PT: Um reenvio está em andamento.
  final bool resending;
  final ApiFailure? failure;
}

/// Step 3: the code was accepted; the user picks the new password (the reset token is NOT here).
/// PT: Passo 3: o código foi aceito; o usuário escolhe a nova senha (o reset token NÃO está aqui).
final class PasswordResetNewPassword extends PasswordResetState {
  const PasswordResetNewPassword({this.busy = false, this.failure});

  final bool busy;
  final ApiFailure? failure;
}

/// The password changed and every session was revoked by the server.
/// PT: A senha mudou e o servidor revogou todas as sessões.
final class PasswordResetDone extends PasswordResetState {
  const PasswordResetDone();
}

/// Business state of the password reset: request a code, verify it, set the new password, resend.
/// PT: Estado de negócio da troca de senha: pedir um código, verificá-lo, definir a nova senha, reenviar.
/// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
class PasswordResetViewModel extends ChangeNotifier {
  PasswordResetViewModel({
    required this._auth,
    Duration cooldown = const Duration(seconds: 60),
    this._successPause = const Duration(milliseconds: 600),
    CooldownTicker ticker = Timer.periodic,
  }) {
    _cooldown = ResendCooldown(onChanged: _notify, duration: cooldown, ticker: ticker);
  }

  final AuthRepository _auth;
  final Duration _successPause;
  late final ResendCooldown _cooldown;
  PasswordResetState _state = const PasswordResetEnterEmail();
  bool _disposed = false;

  // The reset token: only here, in memory; never in the state, a URL, a route extra, storage or a log.
  // PT: O reset token: só aqui, na memória; nunca no estado, numa URL, num extra de rota, no storage ou num log.
  // Notes: docs/code-notes/app-auth.md#resetgrant
  ResetGrant? _grant;

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

  /// Step 2, called when the 6th digit is typed. `invalid-code` (or any failure) goes to `error`;
  /// success shows `success` for a moment, keeps the reset token and moves to step 3.
  /// PT: Passo 2, chamado quando o 6º dígito é digitado. `invalid-code` (ou qualquer falha) vai para `error`;
  /// o sucesso mostra `success` por um instante, guarda o reset token e vai ao passo 3.
  /// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
  Future<void> verifyCode(String code) async {
    if (_state case PasswordResetEnterCode(
      :final email,
      :final status,
      resending: false,
    ) when status == CodeEntryStatus.idle || status == CodeEntryStatus.error) {
      _emit(PasswordResetEnterCode(email, status: CodeEntryStatus.verifying));
      final ResetGrant grant;
      try {
        grant = await _auth.verifyPasswordResetCode(
          PasswordResetVerifyRequest(email: email, code: code),
        );
      } on ApiFailure catch (failure) {
        _emit(PasswordResetEnterCode(email, status: CodeEntryStatus.error, failure: failure));
        return;
      }
      _grant = grant;
      _cooldown.cancel();
      _emit(PasswordResetEnterCode(email, status: CodeEntryStatus.success));
      await Future<void>.delayed(_successPause);
      // The user may have left (dispose) during the pause.
      // PT: O usuário pode ter saído (dispose) durante a pausa.
      if (_disposed) return;
      if (_state case PasswordResetEnterCode(status: CodeEntryStatus.success)) {
        _emit(const PasswordResetNewPassword());
      }
    }
  }

  /// Step 3. `invalid-reset-token` drops the token and returns to step 1 with the failure; success ends the flow.
  /// PT: Passo 3. `invalid-reset-token` descarta o token e volta ao passo 1 com a falha; o sucesso encerra o fluxo.
  /// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
  Future<void> confirm(String newPassword) async {
    final grant = _grant;
    if (grant == null) return;
    if (_state case PasswordResetNewPassword(busy: false)) {
      _emit(const PasswordResetNewPassword(busy: true));
      try {
        await _auth.confirmPasswordReset(
          PasswordResetConfirmRequest(resetToken: grant.token, newPassword: newPassword),
        );
        _grant = null;
        _emit(const PasswordResetDone());
      } on ApiFailure catch (failure) {
        if (failure is ProblemFailure && failure.type == ProblemType.invalidResetToken) {
          _grant = null;
          _emit(PasswordResetEnterEmail(failure: failure));
        } else {
          _emit(PasswordResetNewPassword(failure: failure));
        }
      }
    }
  }

  /// Back to step 1 (fix the address, or start over); the token and the cooldown no longer apply.
  /// PT: Volta ao passo 1 (corrigir o endereço ou recomeçar); o token e a espera deixam de valer.
  /// Notes: docs/code-notes/app-auth.md#passwordresetviewmodel
  void backToEmail() {
    final canLeave = switch (_state) {
      PasswordResetEnterCode(:final status, resending: false) =>
        status == CodeEntryStatus.idle || status == CodeEntryStatus.error,
      PasswordResetNewPassword(busy: false) => true,
      _ => false,
    };
    if (!canLeave) return;
    _grant = null;
    _cooldown.cancel();
    _emit(const PasswordResetEnterEmail());
  }

  /// Asks for a new code; ignored during the cooldown or while busy.
  /// PT: Pede um novo código; ignorado durante a espera ou ocupado.
  Future<void> resend() async {
    if (_state case PasswordResetEnterCode(:final email, :final status, resending: false)
        when _cooldown.remaining == 0 &&
            (status == CodeEntryStatus.idle || status == CodeEntryStatus.error)) {
      _emit(PasswordResetEnterCode(email, resending: true));
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

  /// Drops a stale error once the user edits a field (or starts retyping the code).
  /// PT: Descarta um erro antigo quando o usuário edita um campo (ou volta a digitar o código).
  void clearFailure() {
    switch (_state) {
      case PasswordResetEnterEmail(failure: != null):
        _emit(const PasswordResetEnterEmail());
      case PasswordResetEnterCode(:final email, :final status, failure: != null)
          when status == CodeEntryStatus.idle || status == CodeEntryStatus.error:
        _emit(PasswordResetEnterCode(email));
      case PasswordResetNewPassword(busy: false, failure: != null):
        _emit(const PasswordResetNewPassword());
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
    _grant = null;
    _cooldown.cancel();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/features/auth/_shared/application/code_entry_status.dart';
import 'package:snapledger/features/auth/_shared/application/resend_cooldown.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/email_verification_repository.dart';
import 'package:snapledger/features/profile/_shared/data/models/user_model.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';

/// What the Verify email screen shows; the View draws it and never sees a message string.
/// PT: O que a tela de verificar email mostra; a View o desenha e nunca recebe uma string de mensagem.
/// Notes: docs/code-notes/app-auth.md#verifyemailviewmodel
@immutable
sealed class VerifyEmailState {
  const VerifyEmailState();
}

/// Loading the profile, which gives the address the code goes to.
/// PT: Carregando o perfil, que dá o endereço para onde o código vai.
final class VerifyEmailLoading extends VerifyEmailState {
  const VerifyEmailLoading();
}

final class VerifyEmailLoadFailed extends VerifyEmailState {
  const VerifyEmailLoadFailed(this.failure);

  final ApiFailure failure;
}

/// Waiting for the code typed by the user; [failure] is the last send or confirm that failed.
/// PT: Esperando o código digitado pelo usuário; [failure] é o último envio ou confirmação que falhou.
final class VerifyEmailReady extends VerifyEmailState {
  const VerifyEmailReady(
    this.email, {
    this.status = CodeEntryStatus.idle,
    this.resending = false,
    this.failure,
  });

  final String email;
  final CodeEntryStatus status;

  /// A (re)send is in flight.
  /// PT: Um (re)envio está em andamento.
  final bool resending;
  final ApiFailure? failure;
}

/// The server confirmed the email; [user] is the updated profile.
/// PT: O servidor confirmou o email; [user] é o perfil atualizado.
final class VerifyEmailVerified extends VerifyEmailState {
  const VerifyEmailVerified(this.user);

  final UserModel user;
}

/// Business state of the Verify email screen: load the address, send and confirm the code, skip.
/// PT: Estado de negócio da tela de verificar email: carregar o endereço, enviar e confirmar o código, pular.
/// Notes: docs/code-notes/app-auth.md#verifyemailviewmodel
class VerifyEmailViewModel extends ChangeNotifier {
  VerifyEmailViewModel({
    required this._users,
    required this._verification,
    required this._pending,
    Duration cooldown = const Duration(seconds: 60),
    this._successPause = const Duration(milliseconds: 600),
    CooldownTicker ticker = Timer.periodic,
  }) : afterRegister = _pending.isPending {
    _cooldown = ResendCooldown(onChanged: _notify, duration: cooldown, ticker: ticker);
  }

  final UserRepository _users;
  final EmailVerificationRepository _verification;
  final PendingVerification _pending;
  final Duration _successPause;
  late final ResendCooldown _cooldown;
  VerifyEmailState _state = const VerifyEmailLoading();
  bool _disposed = false;

  /// True when the screen opened right after register, which already emailed a code.
  /// PT: Verdadeiro quando a tela abriu logo após o cadastro, que já enviou um código por email.
  /// Notes: docs/code-notes/app-auth.md#pending-verification
  final bool afterRegister;

  VerifyEmailState get state => _state;

  /// Seconds until a resend is allowed; 0 when it is.
  /// PT: Segundos até um reenvio ser permitido; 0 quando é.
  int get cooldownSeconds => _cooldown.remaining;

  /// Loads the address (also the retry). After register the code is already on its way, so only the
  /// cooldown starts; from the profile a code is sent now.
  /// PT: Carrega o endereço (também o retry). Após o cadastro o código já está a caminho, então só a
  /// espera começa; vindo do perfil, um código é enviado agora.
  /// Notes: docs/code-notes/app-auth.md#verifyemailviewmodel
  Future<void> start() async {
    if (_state is! VerifyEmailLoading) _emit(const VerifyEmailLoading());
    final UserModel user;
    try {
      user = await _users.fetchCurrent();
    } on ApiFailure catch (failure) {
      _emit(VerifyEmailLoadFailed(failure));
      return;
    }
    if (user.emailVerified) {
      _emit(VerifyEmailVerified(user));
      return;
    }
    _emit(VerifyEmailReady(user.email));
    if (afterRegister) {
      _startCooldown();
    } else {
      await sendCode();
    }
  }

  /// Asks for a code; ignored during the cooldown or while busy. A refusal (`429`) also waits.
  /// PT: Pede um código; ignorado durante a espera ou ocupado. Uma recusa (`429`) também espera.
  Future<void> sendCode() async {
    if (_state case VerifyEmailReady(:final email, :final status, resending: false)
        when _cooldown.remaining == 0 && _canType(status)) {
      _emit(VerifyEmailReady(email, resending: true));
      try {
        await _verification.sendCode();
        _emit(VerifyEmailReady(email));
      } on ApiFailure catch (failure) {
        _emit(VerifyEmailReady(email, failure: failure));
      }
      _startCooldown();
    }
  }

  static bool _canType(CodeEntryStatus status) =>
      status == CodeEntryStatus.idle || status == CodeEntryStatus.error;

  /// Called when the 6th digit is typed: any failure goes to `error`; success shows `success` for a
  /// moment, then moves to verified (the Controller leaves the screen).
  /// PT: Chamado quando o 6º dígito é digitado: qualquer falha vai para `error`; o sucesso mostra `success`
  /// por um instante, depois vai para verificado (o Controller sai da tela).
  Future<void> confirm(String code) async {
    if (_state case VerifyEmailReady(:final email, :final status, resending: false)
        when _canType(status)) {
      _emit(VerifyEmailReady(email, status: CodeEntryStatus.verifying));
      final UserModel user;
      try {
        user = await _verification.confirm(code);
      } on ApiFailure catch (failure) {
        _emit(VerifyEmailReady(email, status: CodeEntryStatus.error, failure: failure));
        return;
      }
      _cooldown.cancel();
      _emit(VerifyEmailReady(email, status: CodeEntryStatus.success));
      await Future<void>.delayed(_successPause);
      if (_disposed) return;
      if (_state case VerifyEmailReady(status: CodeEntryStatus.success)) {
        _emit(VerifyEmailVerified(user));
      }
    }
  }

  /// Ends the pending verification (after register); harmless when opened from the profile.
  /// PT: Encerra a verificação pendente (após o cadastro); inofensivo quando aberta pelo perfil.
  /// Notes: docs/code-notes/app-auth.md#pending-verification
  void skip() => _pending.clear();

  /// Drops a stale error once the user edits the code.
  /// PT: Descarta um erro antigo quando o usuário edita o código.
  void clearFailure() {
    if (_state case VerifyEmailReady(:final email, :final status, failure: != null)
        when _canType(status)) {
      _emit(VerifyEmailReady(email));
    }
  }

  void _emit(VerifyEmailState next) {
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

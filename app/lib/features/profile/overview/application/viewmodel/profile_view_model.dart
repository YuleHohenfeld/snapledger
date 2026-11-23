import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/profile/_shared/data/models/user_model.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';

/// What the profile screen shows; the View draws it and never sees a message string.
/// PT: O que a tela de perfil mostra; a View o desenha e nunca recebe uma string de mensagem.
/// Notes: docs/code-notes/app-profile.md#profileviewmodel
@immutable
sealed class ProfileState {
  const ProfileState();
}

final class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

final class ProfileLoaded extends ProfileState {
  const ProfileLoaded(this.user);

  final UserModel user;
}

final class ProfileFailed extends ProfileState {
  const ProfileFailed(this.failure);

  /// The [ApiFailure] to localize.
  /// PT: O [ApiFailure] a traduzir.
  final ApiFailure failure;
}

/// Business state of the profile: loads the user and signs out.
/// PT: Estado de negócio do perfil: carrega o usuário e faz o logout.
/// Notes: docs/code-notes/app-profile.md#profileviewmodel
class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({required this._users, required this._auth, required this._session});

  final UserRepository _users;
  final AuthRepository _auth;
  final SessionNotifier _session;
  ProfileState _state = const ProfileLoading();
  bool _loggingOut = false;
  bool _disposed = false;

  ProfileState get state => _state;

  /// True from the tap on sign out until the router leaves the screen.
  /// PT: Verdadeiro do toque em sair até o router sair da tela.
  bool get loggingOut => _loggingOut;

  /// Loads the profile, also used to retry; ignored while signing out.
  /// PT: Carrega o perfil, também usado para tentar de novo; ignorado durante o logout.
  Future<void> load() async {
    if (_loggingOut || _disposed) return;
    // Already loading on the first call (from initState): no notify during build.
    // PT: Já está carregando na primeira chamada (do initState): sem notify durante o build.
    if (_state is! ProfileLoading) _emit(const ProfileLoading());
    try {
      _emit(ProfileLoaded(await _users.fetchCurrent()));
    } on ApiFailure catch (failure) {
      _emit(ProfileFailed(failure));
    }
  }

  /// Revokes on the server best effort, then wipes locally whatever happened; ignored if already running.
  /// PT: Revoga no servidor com melhor esforço e depois limpa localmente aconteça o que acontecer; ignorado se já rodando.
  /// Notes: docs/code-notes/app-profile.md#profileviewmodel
  Future<void> logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    _notify();
    var done = false;
    try {
      await _session.signOut(revoke: _auth.logout);
      done = true;
    } finally {
      // A throwing wipe must not leave the button disabled forever; on success it stays disabled
      // until the router leaves the screen.
      // PT: Um wipe que lança não pode deixar o botão desativado para sempre; no sucesso ele fica
      // desativado até o router sair da tela.
      if (!done) {
        _loggingOut = false;
        _notify();
      }
    }
  }

  void _emit(ProfileState next) {
    _state = next;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

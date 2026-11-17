import 'dart:async';

import 'package:snapledger/features/profile/_shared/data/models/user_model.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';

import 'json_fixtures.dart';

/// A [UserRepository] that answers with a made-up user, or throws [failure].
/// PT: Um [UserRepository] que responde com um usuário inventado, ou lança [failure].
class FakeUserRepository implements UserRepository {
  Exception? failure;

  /// When set, every call waits for it, so a test can act while the request is in flight.
  /// PT: Quando definido, toda chamada espera por ele, para o teste agir com a requisição em andamento.
  Completer<void>? gate;

  int calls = 0;

  @override
  Future<UserModel> fetchCurrent() async {
    calls++;
    await gate?.future;
    if (failure case final failure?) throw failure;
    return UserModel.fromJson(fakeUserJson());
  }
}

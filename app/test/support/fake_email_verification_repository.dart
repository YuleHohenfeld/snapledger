import 'dart:async';

import 'package:snapledger/features/auth/_shared/data/repositories/email_verification_repository.dart';
import 'package:snapledger/features/profile/_shared/data/models/user_model.dart';

import 'json_fixtures.dart';

/// An [EmailVerificationRepository] that records calls and answers, or throws [sendFailure] / [confirmFailure].
/// PT: Um [EmailVerificationRepository] que registra as chamadas e responde, ou lança [sendFailure] / [confirmFailure].
class FakeEmailVerificationRepository implements EmailVerificationRepository {
  Exception? sendFailure;
  Exception? confirmFailure;

  /// When set, every call waits for it, so a test can act while the request is in flight.
  /// PT: Quando definido, toda chamada espera por ele, para o teste agir com a requisição em andamento.
  Completer<void>? gate;

  int sends = 0;
  final List<String> confirms = [];

  @override
  Future<void> sendCode() async {
    sends++;
    await gate?.future;
    if (sendFailure case final failure?) throw failure;
  }

  @override
  Future<UserModel> confirm(String code) async {
    confirms.add(code);
    await gate?.future;
    if (confirmFailure case final failure?) throw failure;
    return UserModel.fromJson(fakeUserJson(emailVerified: true));
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/verify_email/application/controller/verify_email_controller.dart';
import 'package:snapledger/features/auth/verify_email/application/viewmodel/verify_email_view_model.dart';

import '../../../../../support/fake_email_verification_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/fake_user_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeEmailVerificationRepository verification;
  late FakeNavigator navigator;
  late SessionNotifier session;
  late PendingVerification pending;
  late VerifyEmailViewModel viewModel;
  late VerifyEmailController controller;

  Future<void> open({required bool afterRegister}) async {
    if (afterRegister) pending.begin();
    viewModel = VerifyEmailViewModel(
      users: FakeUserRepository(),
      verification: verification,
      pending: pending,
      successPause: Duration.zero,
    );
    controller = VerifyEmailController(viewModel: viewModel, navigator: navigator);
    await viewModel.start();
  }

  setUp(() {
    verification = FakeEmailVerificationRepository();
    navigator = FakeNavigator();
    session = inMemorySession().session;
    pending = PendingVerification(session: session);
  });

  tearDown(() {
    controller.dispose();
    viewModel.dispose();
    pending.dispose();
    session.dispose();
  });

  test('a malformed code is not sent', () async {
    await open(afterRegister: false);

    await controller.onCodeCompleted('123');

    expect(verification.confirms, isEmpty);
  });

  test('a completed code is confirmed and leaves the screen by itself (profile: pop)', () async {
    await open(afterRegister: false);

    await controller.onCodeCompleted('042917');

    expect(verification.confirms, ['042917']);
    expect(navigator.pops, 1);
  });

  test('a completed code after register clears the flag and goes to the summary', () async {
    await open(afterRegister: true);

    await controller.onCodeCompleted('042917');

    expect(pending.isPending, isFalse);
    expect(navigator.wentTo, [AppRoute.summary]);
  });

  test('a refused code clears the boxes, stays on the screen and keeps the flag', () async {
    await open(afterRegister: true);
    verification.confirmFailure = const ProblemFailure(status: 400, type: ProblemType.invalidCode);
    controller.codeField.text = '000000';

    await controller.onCodeCompleted('000000');

    expect(controller.codeField.text, isEmpty);
    expect(viewModel.state, isA<VerifyEmailReady>().having((s) => s.failure, 'f', isNotNull));
    expect(pending.isPending, isTrue);
    expect(navigator.wentTo, isEmpty);
    expect(navigator.pops, 0);
  });

  test('typing again after an error removes it', () async {
    await open(afterRegister: false);
    verification.confirmFailure = const ProblemFailure(status: 400, type: ProblemType.invalidCode);
    await controller.onCodeCompleted('000000');

    controller.onCodeEdited('1');

    expect(viewModel.state, isA<VerifyEmailReady>().having((s) => s.failure, 'f', isNull));
  });

  test('resend asks the ViewModel for a new code once the cooldown is over', () async {
    await open(afterRegister: false);
    controller.onResend();

    // Refused: the cooldown started with the first send.
    // PT: Recusado: a espera começou com o primeiro envio.
    expect(verification.sends, 1);
  });

  test('skip after register clears the flag and goes to the summary', () async {
    await open(afterRegister: true);

    controller.onSkipTapped();

    expect(pending.isPending, isFalse);
    expect(navigator.wentTo, [AppRoute.summary]);
    expect(navigator.pops, 0);
  });

  test('skip from the profile pops back', () async {
    await open(afterRegister: false);

    controller.onSkipTapped();

    expect(navigator.pops, 1);
    expect(navigator.wentTo, isEmpty);
  });

  test('continue (already verified) leaves like skipping', () async {
    await open(afterRegister: false);

    controller.onContinueTapped();

    expect(navigator.pops, 1);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
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

  test('validates the code', () async {
    await open(afterRegister: false);

    expect(controller.codeError('12345'), AuthFieldError.codeInvalid);
    expect(controller.codeError('042917'), isNull);
  });

  test('an invalid code is not sent', () async {
    await open(afterRegister: false);
    controller.codeField.text = '123';

    await controller.onSubmit();

    expect(verification.confirms, isEmpty);
  });

  test('a valid code is confirmed', () async {
    await open(afterRegister: false);
    controller.codeField.text = '042917';

    await controller.onSubmit();

    expect(verification.confirms, ['042917']);
    expect(viewModel.state, isA<VerifyEmailVerified>());
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

  test('continue after a successful verification leaves like skipping', () async {
    await open(afterRegister: false);
    controller.codeField.text = '042917';
    await controller.onSubmit();

    controller.onContinueTapped();

    expect(navigator.pops, 1);
  });
}

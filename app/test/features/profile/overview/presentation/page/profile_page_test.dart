import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';
import 'package:snapledger/features/profile/overview/presentation/page/profile_page.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../../support/fake_auth_repository.dart';
import '../../../../../support/fake_navigator.dart';
import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/fake_user_repository.dart';
import '../../../../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeUserRepository users;
  late FakeAuthRepository auth;
  late SessionNotifier session;
  late FakeNavigator navigator;

  setUp(() async {
    navigator = FakeNavigator();
    users = FakeUserRepository();
    auth = FakeAuthRepository();
    session = inMemorySession().session;
    await session.signIn(auth.response.tokens);
  });

  tearDown(() => session.dispose());

  Future<void> pumpProfile(WidgetTester tester) => pumpApp(
    tester,
    const ProfilePage(),
    providers: [
      Provider<UserRepository>.value(value: users),
      Provider<AuthRepository>.value(value: auth),
      ChangeNotifierProvider<SessionNotifier>.value(value: session),
      Provider<AppNavigator>.value(value: navigator),
    ],
  );

  testWidgets('shows the verify email banner only while the email is not verified', (
    tester,
  ) async {
    await pumpProfile(tester);
    await tester.pump();
    expect(find.text(l10n.profileVerifyEmailBanner), findsOneWidget);
    expect(find.text(l10n.profileVerifyEmailAction), findsOneWidget);
  });

  testWidgets('no banner for a verified email', (tester) async {
    users.emailVerified = true;

    await pumpProfile(tester);
    await tester.pump();

    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text(l10n.profileVerifyEmailBanner), findsNothing);
  });

  testWidgets('the banner opens the verification and reloads the profile when it closes', (
    tester,
  ) async {
    await pumpProfile(tester);
    await tester.pump();
    expect(users.calls, 1);

    await tester.tap(find.text(l10n.profileVerifyEmailAction));
    await tester.pump();
    expect(navigator.pushed, [AppRoute.verifyEmail]);
    expect(users.calls, 1);

    users.emailVerified = true;
    navigator.completePush();
    await tester.pump();
    await tester.pump();

    expect(users.calls, 2);
    expect(find.text(l10n.profileVerifyEmailBanner), findsNothing);
  });

  testWidgets('signing out while the verification is open does not reload a disposed profile', (
    tester,
  ) async {
    await pumpProfile(tester);
    await tester.pump();
    await tester.tap(find.text(l10n.profileVerifyEmailAction));
    await tester.pump();

    // The router would drop the profile (sign out) while the pushed screen is still open.
    // PT: O router descartaria o perfil (logout) enquanto a tela empilhada ainda está aberta.
    await tester.pumpWidget(const SizedBox.shrink());
    navigator.completePush();
    await tester.pump();
    await tester.pump();

    expect(users.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows name, email and currency', (tester) async {
    await pumpProfile(tester);
    await tester.pump();

    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);
    expect(find.text('BRL'), findsOneWidget);
    expect(find.text(l10n.profileLogout), findsOneWidget);
  });

  testWidgets('the Categories row opens the category management screen', (tester) async {
    await pumpProfile(tester);
    await tester.pump();

    await tester.tap(find.text(l10n.profileCategoriesRow));
    await tester.pump();

    expect(navigator.pushed, [AppRoute.categories]);
  });

  testWidgets('a failure shows a message and retry loads again', (tester) async {
    users.failure = const NetworkFailure();
    await pumpProfile(tester);
    await tester.pump();
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    users.failure = null;
    await tester.tap(find.text(l10n.profileRetry));
    await tester.pump();
    await tester.pump();

    expect(find.text('Ana Souza'), findsOneWidget);
  });

  testWidgets('sign out revokes, wipes the session and shows the busy button', (tester) async {
    await pumpProfile(tester);
    await tester.pump();

    await tester.tap(find.text(l10n.profileLogout));
    await tester.pump();

    expect(auth.logouts, ['fake-refresh-1']);
    expect(session.status, SessionStatus.signedOut);
    expect(find.bySemanticsLabel(l10n.profileLoggingOut), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
}

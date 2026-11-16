import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';
import 'package:snapledger/features/profile/overview/presentation/page/profile_page.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../../support/fake_auth_repository.dart';
import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/fake_user_repository.dart';
import '../../../../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeUserRepository users;
  late FakeAuthRepository auth;
  late SessionNotifier session;

  setUp(() async {
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
    ],
  );

  testWidgets('shows name, email and currency', (tester) async {
    await pumpProfile(tester);
    await tester.pump();

    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);
    expect(find.text('BRL'), findsOneWidget);
    expect(find.text(l10n.profileLogout), findsOneWidget);
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/features/auth/splash/presentation/page/splash_page.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../../support/fake_session_refresher.dart';
import '../../../../../support/in_memory_secure_store.dart';
import '../../../../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeSessionRefresher refresher;
  late SessionNotifier session;

  setUp(() {
    refresher = FakeSessionRefresher(() async => const TemporaryFailure());
    session = SessionNotifier(tokens: TokenStore(InMemorySecureStore()), refresher: refresher);
  });

  tearDown(() => session.dispose());

  Future<void> pumpSplash(WidgetTester tester) => pumpApp(
    tester,
    const SplashPage(),
    providers: [ChangeNotifierProvider<SessionNotifier>.value(value: session)],
  );

  testWidgets('shows a labeled progress indicator while the session is checked', (tester) async {
    final gate = Completer<RefreshOutcome>();
    refresher.onRefresh = () => gate.future;

    await pumpSplash(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel(l10n.splashLoadingSemantics), findsOneWidget);
    gate.complete(const SessionEnded());
    await tester.pump();
  });

  testWidgets('without a verdict shows the message, retry and sign in again', (tester) async {
    await pumpSplash(tester);
    await tester.pump();

    expect(find.text(l10n.splashRetryMessage), findsOneWidget);
    expect(find.text(l10n.splashRetry), findsOneWidget);
    expect(find.text(l10n.splashSignInAgain), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('"Try again" checks the session again', (tester) async {
    await pumpSplash(tester);
    await tester.pump();

    await tester.tap(find.text(l10n.splashRetry));
    await tester.pump();

    expect(refresher.calls, 2);
  });

  testWidgets('"Sign in again" wipes the session', (tester) async {
    await pumpSplash(tester);
    await tester.pump();

    await tester.tap(find.text(l10n.splashSignInAgain));
    await tester.pump();

    expect(session.status, SessionStatus.signedOut);
  });
}

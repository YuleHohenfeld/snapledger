import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/router/redirect.dart';
import 'package:snapledger/core/session/pending_verification.dart';
import 'package:snapledger/core/session/session_notifier.dart';

/// The app's one router: starts on the splash and re-runs [redirectFor] whenever the session changes.
/// PT: O único router do app: começa no splash e reexecuta o [redirectFor] sempre que a sessão muda.
/// Notes: docs/code-notes/app-core.md#approuter
GoRouter buildRouter(
  SessionNotifier session,
  PendingVerification pending,
  List<RouteBase> routes,
) => GoRouter(
  initialLocation: AppRoute.splash.path,
  refreshListenable: Listenable.merge([session, pending]),
  redirect: (context, state) =>
      redirectFor(session.status, state.uri, pendingVerification: pending.isPending),
  routes: routes,
);

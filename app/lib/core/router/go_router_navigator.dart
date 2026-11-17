import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:snapledger/core/router/app_navigator.dart';

/// [AppNavigator] over the app's one [GoRouter]; Controllers see only the interface.
/// PT: [AppNavigator] sobre o único [GoRouter] do app; os Controllers só enxergam a interface.
/// Notes: docs/code-notes/app-core.md#gorouternavigator
final class GoRouterNavigator implements AppNavigator {
  const GoRouterNavigator(this._router);

  final GoRouter _router;

  @override
  void goTo(AppRoute route) => _router.go(route.path);

  @override
  void push(AppRoute route) => unawaited(_router.push<void>(route.path));
}

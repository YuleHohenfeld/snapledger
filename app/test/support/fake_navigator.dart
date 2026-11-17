import 'package:snapledger/core/router/app_navigator.dart';

/// An [AppNavigator] that only records the intents it receives.
/// PT: Um [AppNavigator] que só registra as intenções que recebe.
class FakeNavigator implements AppNavigator {
  final List<AppRoute> wentTo = [];
  final List<AppRoute> pushed = [];

  @override
  void goTo(AppRoute route) => wentTo.add(route);

  @override
  void push(AppRoute route) => pushed.add(route);
}

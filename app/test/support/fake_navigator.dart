import 'dart:async';

import 'package:snapledger/core/router/app_navigator.dart';

/// An [AppNavigator] that only records the intents it receives.
/// PT: Um [AppNavigator] que só registra as intenções que recebe.
class FakeNavigator implements AppNavigator {
  final List<AppRoute> wentTo = [];
  final List<AppRoute> pushed = [];
  final List<String> pushedExpenseEdits = [];
  int pops = 0;

  // Created inside push() so it lives in the zone of the test body (a widget test's fake clock).
  // PT: Criado dentro do push() para viver na zona do corpo do teste (o relógio falso de um widget test).
  Completer<void>? _pushResult;

  @override
  void goTo(AppRoute route) => wentTo.add(route);

  @override
  Future<void> push(AppRoute route) {
    pushed.add(route);
    return (_pushResult = Completer<void>()).future;
  }

  @override
  Future<void> pushExpenseEdit(String id) {
    pushedExpenseEdits.add(id);
    return (_pushResult = Completer<void>()).future;
  }

  /// Simulates the last pushed screen being popped: completes the Future [push] returned.
  /// PT: Simula a última tela empilhada sendo fechada: completa o Future que o [push] devolveu.
  void completePush() => _pushResult?.complete();

  @override
  void pop() => pops++;
}

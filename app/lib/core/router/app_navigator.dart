/// Every location of the app, typed, so no screen spreads path strings around.
/// PT: Todo endereço do app, tipado, para que nenhuma tela espalhe strings de caminho.
/// Notes: docs/code-notes/app-core.md#appnavigator
enum AppRoute {
  splash('/splash'),
  login('/login'),
  register('/register'),
  summary('/summary'),
  expenses('/expenses'),
  profile('/profile'),
  categories('/profile/categories');

  const AppRoute(this.path);

  final String path;
}

/// Navigation intents of Controllers, faked in tests; [GoRouterNavigator] is the real one.
/// PT: Intenções de navegação dos Controllers, falsificadas nos testes; o [GoRouterNavigator] é o real.
/// Notes: docs/code-notes/app-core.md#appnavigator
abstract interface class AppNavigator {
  /// Replaces the current location (no back entry).
  /// PT: Substitui o endereço atual (sem entrada de voltar).
  void goTo(AppRoute route);

  /// Opens [route] on top of the current one.
  /// PT: Abre [route] por cima do atual.
  void push(AppRoute route);
}

/// Every location of the app, typed, so no screen spreads path strings around.
/// PT: Todo endereço do app, tipado, para que nenhuma tela espalhe strings de caminho.
/// Notes: docs/code-notes/app-core.md#appnavigator
enum AppRoute {
  splash('/splash'),
  login('/login'),
  register('/register'),
  passwordReset('/forgot-password'),
  verifyEmail('/verify-email'),
  summary('/summary'),
  expenses('/expenses'),
  expenseNew('/expenses/new'),
  profile('/profile'),
  categories('/profile/categories');

  const AppRoute(this.path);

  final String path;

  /// The location of the edit screen of expense [id], percent-encoded as one path segment.
  /// PT: O endereço da tela de edição do gasto [id], codificado como um só segmento de caminho.
  /// Notes: docs/code-notes/app-expenses.md#routes
  static String expenseEditPath(String id) => '/expenses/${Uri.encodeComponent(id)}';
}

/// Navigation intents of Controllers, faked in tests; [GoRouterNavigator] is the real one.
/// PT: Intenções de navegação dos Controllers, falsificadas nos testes; o [GoRouterNavigator] é o real.
/// Notes: docs/code-notes/app-core.md#appnavigator
abstract interface class AppNavigator {
  /// Replaces the current location (no back entry).
  /// PT: Substitui o endereço atual (sem entrada de voltar).
  void goTo(AppRoute route);

  /// Opens [route] on top of the current one; completes when it is popped, so the caller can reload.
  /// PT: Abre [route] por cima do atual; completa quando ela é fechada, para quem chamou recarregar.
  Future<void> push(AppRoute route);

  /// Opens the edit screen of expense [id] on top of the current one; completes when it is popped.
  /// PT: Abre a tela de edição do gasto [id] por cima da atual; completa quando ela é fechada.
  Future<void> pushExpenseEdit(String id);

  /// Closes the current location, back to the one below it.
  /// PT: Fecha o endereço atual, voltando ao que está abaixo.
  void pop();
}

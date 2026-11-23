import 'dart:async';

import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_model.dart';
import 'package:snapledger/features/expenses/list/application/viewmodel/expense_list_view_model.dart';

/// Turns taps on the expense list into ViewModel calls and navigation intents; it holds no state.
/// PT: Transforma toques na lista de gastos em chamadas ao ViewModel e intenções de navegação; não guarda estado.
/// Notes: docs/code-notes/app-expenses.md#expenselistcontroller
class ExpenseListController {
  ExpenseListController({required this._viewModel, required this._navigator});

  final ExpenseListViewModel _viewModel;
  final AppNavigator _navigator;

  void start() => unawaited(_viewModel.load());

  void onRetryTapped() => unawaited(_viewModel.load());

  void onPreviousMonthTapped() => unawaited(_viewModel.showPreviousMonth());

  void onNextMonthTapped() => unawaited(_viewModel.showNextMonth());

  /// Pull to refresh; the returned future ends the spinner.
  /// PT: Puxar para atualizar; o future devolvido encerra o spinner.
  Future<void> onRefresh() => _viewModel.refresh();

  /// The list reloads by itself when the form saves (the repository's `changes`), so nothing waits here.
  /// PT: A lista recarrega sozinha quando o formulário salva (o `changes` do repositório), então nada espera aqui.
  void onAddTapped() => unawaited(_navigator.push(AppRoute.expenseNew));

  void onExpenseTapped(ExpenseModel expense) => unawaited(_navigator.pushExpenseEdit(expense.id));
}

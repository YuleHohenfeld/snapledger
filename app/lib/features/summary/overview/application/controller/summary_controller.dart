import 'dart:async';

import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/summary/overview/application/viewmodel/summary_view_model.dart';

/// Turns taps on the summary into ViewModel calls and navigation intents; it holds no state.
/// PT: Transforma toques no resumo em chamadas ao ViewModel e intenções de navegação; não guarda estado.
/// Notes: docs/code-notes/app-summary.md#summarycontroller
class SummaryController {
  SummaryController({required this._viewModel, required this._navigator});

  final SummaryViewModel _viewModel;
  final AppNavigator _navigator;

  void start() => unawaited(_viewModel.load());

  void onRetryTapped() => unawaited(_viewModel.load());

  void onPreviousMonthTapped() => unawaited(_viewModel.showPreviousMonth());

  void onNextMonthTapped() => unawaited(_viewModel.showNextMonth());

  /// Pull to refresh; the returned future ends the spinner.
  /// PT: Puxar para atualizar; o future devolvido encerra o spinner.
  Future<void> onRefresh() => _viewModel.refresh();

  /// From the empty state. The summary reloads by itself when the form saves (the repository's `changes`).
  /// PT: Do estado vazio. O resumo recarrega sozinho quando o formulário salva (o `changes` do repositório).
  void onAddExpenseTapped() => unawaited(_navigator.push(AppRoute.expenseNew));
}

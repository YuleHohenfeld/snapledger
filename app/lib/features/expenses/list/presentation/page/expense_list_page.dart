import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/widgets/month_selector.dart';
import 'package:snapledger/features/expenses/_shared/presentation/expense_load_error.dart';
import 'package:snapledger/features/expenses/list/application/controller/expense_list_controller.dart';
import 'package:snapledger/features/expenses/list/application/viewmodel/expense_list_view_model.dart';
import 'package:snapledger/features/expenses/list/presentation/widgets/expense_list_content.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The Expenses tab: a month selector, the month's expenses grouped by day, and a button to add one.
/// PT: A aba Despesas: um seletor de mês, os gastos do mês agrupados por dia e um botão para adicionar um.
/// Notes: docs/code-notes/app-expenses.md#expenselistpage
class ExpenseListPage extends StatelessWidget {
  /// [now] is the clock of "this month" and "Today"; tests pass a fixed one.
  /// PT: [now] é o relógio de "este mês" e "Hoje"; os testes passam um fixo.
  const ExpenseListPage({super.key, this.now = DateTime.now});

  final DateTime Function() now;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) => ExpenseListViewModel(expenses: context.read(), users: context.read(), now: now),
    child: const _ExpenseListView(),
  );
}

class _ExpenseListView extends StatefulWidget {
  const _ExpenseListView();

  @override
  State<_ExpenseListView> createState() => _ExpenseListViewState();
}

class _ExpenseListViewState extends State<_ExpenseListView> {
  late final ExpenseListController _controller;

  static const _maxWidth = 560.0;

  @override
  void initState() {
    super.initState();
    _controller = ExpenseListController(
      viewModel: context.read<ExpenseListViewModel>(),
      navigator: context.read(),
    )..start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.select((ExpenseListViewModel vm) => vm.state);
    final canGoNext = context.select((ExpenseListViewModel vm) => vm.canGoNext);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.expensesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _controller.onAddTapped,
        icon: const Icon(Icons.add),
        label: Text(l10n.expenseListAdd),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Column(
              children: [
                MonthSelector(
                  month: state.month,
                  canGoNext: canGoNext,
                  onPrevious: _controller.onPreviousMonthTapped,
                  onNext: _controller.onNextMonthTapped,
                ),
                Expanded(
                  child: switch (state) {
                    ExpenseListLoading() => const Center(child: CircularProgressIndicator()),
                    ExpenseListFailed(:final failure) => ExpenseLoadError(
                      failure: failure,
                      onRetry: _controller.onRetryTapped,
                    ),
                    ExpenseListLoaded() => ExpenseListContent(
                      state: state,
                      onRefresh: _controller.onRefresh,
                      onExpenseTap: _controller.onExpenseTapped,
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

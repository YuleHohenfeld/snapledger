import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/widgets/load_error.dart';
import 'package:snapledger/core/design/widgets/month_selector.dart';
import 'package:snapledger/core/design/widgets/responsive_body.dart';
import 'package:snapledger/core/design/window_size.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/summary/overview/application/controller/summary_controller.dart';
import 'package:snapledger/features/summary/overview/application/viewmodel/summary_view_model.dart';
import 'package:snapledger/features/summary/overview/presentation/widgets/summary_content.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The Summary tab: a month selector, the month total with its comparison, and spending per category.
/// PT: A aba Resumo: um seletor de mês, o total do mês com a comparação, e o gasto por categoria.
/// Notes: docs/code-notes/app-summary.md#summarypage
class SummaryPage extends StatelessWidget {
  /// [now] is the clock of "this month"; tests pass a fixed one.
  /// PT: [now] é o relógio de "este mês"; os testes passam um fixo.
  const SummaryPage({super.key, this.now = DateTime.now});

  final DateTime Function() now;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) =>
        SummaryViewModel(summaries: context.read(), expenses: context.read(), now: now),
    child: const _SummaryView(),
  );
}

class _SummaryView extends StatefulWidget {
  const _SummaryView();

  @override
  State<_SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<_SummaryView> {
  late final SummaryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SummaryController(
      viewModel: context.read<SummaryViewModel>(),
      navigator: context.read(),
    )..start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.select((SummaryViewModel vm) => vm.state);
    final canGoNext = context.select((SummaryViewModel vm) => vm.canGoNext);
    return Scaffold(
      // With the shell's top bar the tab name is already on screen: no second title bar.
      // PT: Com a barra superior da moldura o nome da aba já está na tela: sem segunda barra de título.
      appBar: WindowSize.of(context).hasTopBar ? null : AppBar(title: Text(l10n.summaryTitle)),
      body: SafeArea(
        child: ResponsiveBody(
          maxWidth: AppBreakpoints.dashboardWidth,
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
                  SummaryLoading() => const Center(child: CircularProgressIndicator()),
                  SummaryFailed(:final failure) => LoadError(
                    message: failureMessage(l10n, failure) ?? l10n.errorUnexpected,
                    retryLabel: l10n.summaryRetry,
                    onRetry: _controller.onRetryTapped,
                  ),
                  SummaryLoaded() => SummaryContent(
                    state: state,
                    onRefresh: _controller.onRefresh,
                    onAdd: _controller.onAddExpenseTapped,
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

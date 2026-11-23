import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/expenses/_shared/data/repositories/expense_repository.dart';
import 'package:snapledger/features/summary/_shared/data/models/expense_summary_model.dart';
import 'package:snapledger/features/summary/_shared/data/repositories/summary_repository.dart';

/// Whether the month cost more, less or the same as the previous one.
/// PT: Se o mês custou mais, menos ou igual ao anterior.
enum ComparisonDirection { up, down, same }

/// This month against the previous one, exact: the difference and, when it means something, its percent.
/// PT: Este mês contra o anterior, exato: a diferença e, quando faz sentido, o percentual dela.
/// Notes: docs/code-notes/app-summary.md#monthcomparison
@immutable
final class MonthComparison {
  const MonthComparison({required this.difference, required this.direction, this.percent});

  /// Compares [total] with [previous] using only [Decimal]; there is no percent when [previous] is 0
  /// (a share of nothing is not a number worth showing).
  /// PT: Compara [total] com [previous] só com [Decimal]; não há percentual quando [previous] é 0
  /// PT: (uma fatia de nada não é um número que valha mostrar).
  factory MonthComparison.of(Decimal total, Decimal previous) {
    final difference = total - previous;
    final direction = difference > Decimal.zero
        ? ComparisonDirection.up
        : (difference < Decimal.zero ? ComparisonDirection.down : ComparisonDirection.same);
    Decimal? percent;
    if (previous > Decimal.zero) {
      // Rational to Decimal with a fixed scale: the percent is shown with one place, never a double.
      // PT: Rational para Decimal com escala fixa: o percentual é mostrado com uma casa, nunca um double.
      percent = ((difference * Decimal.fromInt(100)) / previous)
          .toDecimal(scaleOnInfinitePrecision: 4)
          .abs();
    }
    return MonthComparison(difference: difference.abs(), direction: direction, percent: percent);
  }

  /// How much more or less was spent, always positive; [direction] says which.
  /// PT: Quanto a mais ou a menos foi gasto, sempre positivo; [direction] diz qual.
  final Decimal difference;
  final ComparisonDirection direction;

  /// The difference as a percent of the previous month, positive; null when the previous month was 0.
  /// PT: A diferença como percentual do mês anterior, positivo; nulo quando o mês anterior foi 0.
  final Decimal? percent;
}

/// What the summary shows; the View draws it and never sees a message string.
/// PT: O que o resumo mostra; a View o desenha e nunca recebe uma string de mensagem.
/// Notes: docs/code-notes/app-summary.md#summaryviewmodel
@immutable
sealed class SummaryState {
  const SummaryState(this.month);

  /// The month this state is about, so the selector shows it in every state.
  /// PT: O mês de que este estado trata, para o seletor mostrá-lo em todo estado.
  final Month month;
}

final class SummaryLoading extends SummaryState {
  const SummaryLoading(super.month);
}

final class SummaryLoaded extends SummaryState {
  SummaryLoaded({required Month month, required this.summary, this.failure})
    : comparison = MonthComparison.of(summary.total, summary.previousMonthTotal),
      super(month);

  final ExpenseSummaryModel summary;
  final MonthComparison comparison;

  /// A refresh that failed, kept typed next to the summary that stays on screen.
  /// PT: Uma atualização que falhou, mantida tipada junto do resumo que continua na tela.
  final ApiFailure? failure;

  /// A month with no expense: the screen offers "Add expense" instead of an empty chart.
  /// PT: Um mês sem gasto: a tela oferece "Adicionar gasto" em vez de um gráfico vazio.
  bool get isEmpty => summary.expenseCount == 0 && summary.byCategory.isEmpty;

  SummaryLoaded withFailure(ApiFailure? value) =>
      SummaryLoaded(month: month, summary: summary, failure: value);
}

final class SummaryFailed extends SummaryState {
  const SummaryFailed(super.month, this.failure);

  final ApiFailure failure;
}

/// Business state of the summary: one month at a time, with the comparison against the previous one.
/// PT: Estado de negócio do resumo: um mês por vez, com a comparação contra o anterior.
/// Notes: docs/code-notes/app-summary.md#summaryviewmodel
class SummaryViewModel extends ChangeNotifier {
  SummaryViewModel({required this._summaries, required this._expenses, required this._now}) {
    _month = Month.of(_now());
    _state = SummaryLoading(_month);
    _expenses.changes.addListener(_onExpensesChanged);
  }

  final SummaryRepository _summaries;
  final ExpenseRepository _expenses;
  final DateTime Function() _now;

  late Month _month;
  late SummaryState _state;
  int _ticket = 0;
  bool _disposed = false;

  SummaryState get state => _state;

  Month get month => _month;

  /// The next month is off beyond the current one: nothing can be dated that far ahead.
  /// PT: O mês seguinte fica desligado além do atual: nada pode ter data tão à frente.
  bool get canGoNext => _month < Month.of(_now());

  /// First load, or "try again" after a failed one.
  /// PT: Primeira carga, ou "tentar de novo" após uma que falhou.
  Future<void> load() async {
    if (_disposed) return;
    final ticket = ++_ticket;
    // Already loading this month on the first call (from initState): no notify during build.
    // PT: Já está carregando este mês na primeira chamada (do initState): sem notify durante o build.
    if (_state is! SummaryLoading || _state.month != _month) _emit(SummaryLoading(_month));
    final next = await _fetch(_month);
    // A newer load (another month, a retry) owns the screen now.
    // PT: Uma carga mais nova (outro mês, um retry) é dona da tela agora.
    if (ticket != _ticket) return;
    _emit(next);
  }

  /// Pull to refresh and reload after a write: the summary stays on screen; a failure is kept next to it.
  /// PT: Puxar para atualizar e recarregar após uma escrita: o resumo fica na tela; uma falha fica junto dele.
  Future<void> refresh() async {
    final current = _state;
    if (_disposed) return;
    if (current is! SummaryLoaded) return load();
    final ticket = ++_ticket;
    final next = await _fetch(_month);
    if (ticket != _ticket) return;
    _emit(switch (next) {
      SummaryFailed(:final failure) => current.withFailure(failure),
      _ => next,
    });
  }

  Future<void> showPreviousMonth() => _show(_month.previous);

  Future<void> showNextMonth() async {
    if (canGoNext) await _show(_month.next);
  }

  Future<void> _show(Month month) {
    _month = month;
    return load();
  }

  Future<SummaryState> _fetch(Month month) async {
    try {
      return SummaryLoaded(month: month, summary: await _summaries.fetch(month));
    } on ApiFailure catch (failure) {
      return SummaryFailed(month, failure);
    }
  }

  void _onExpensesChanged() => unawaited(refresh());

  void _emit(SummaryState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _expenses.changes.removeListener(_onExpensesChanged);
    super.dispose();
  }
}

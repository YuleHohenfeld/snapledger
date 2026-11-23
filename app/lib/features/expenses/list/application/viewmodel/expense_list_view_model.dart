import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/core/time/calendar_date.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_model.dart';
import 'package:snapledger/features/expenses/_shared/data/repositories/expense_repository.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';

/// How a day relates to "now", so the View writes "Today" or "Yesterday" without any date logic.
/// PT: Como um dia se relaciona com "agora", para a View escrever "Hoje" ou "Ontem" sem lógica de data.
enum ExpenseDayKind { today, yesterday, other }

/// The expenses of one calendar day with their exact sum.
/// PT: Os gastos de um dia do calendário com a soma exata deles.
/// Notes: docs/code-notes/app-expenses.md#expenselistviewmodel
@immutable
final class ExpenseDayGroup {
  const ExpenseDayGroup({
    required this.date,
    required this.kind,
    required this.expenses,
    required this.total,
  });

  final DateTime date;
  final ExpenseDayKind kind;
  final List<ExpenseModel> expenses;
  final Decimal total;
}

/// What the expense list shows; the View draws it and never sees a message string.
/// PT: O que a lista de gastos mostra; a View a desenha e nunca recebe uma string de mensagem.
/// Notes: docs/code-notes/app-expenses.md#expenselistviewmodel
@immutable
sealed class ExpenseListState {
  const ExpenseListState(this.month);

  /// The month this state is about, so the selector shows it in every state.
  /// PT: O mês de que este estado trata, para o seletor mostrá-lo em todo estado.
  final Month month;
}

final class ExpenseListLoading extends ExpenseListState {
  const ExpenseListLoading(super.month);
}

final class ExpenseListLoaded extends ExpenseListState {
  const ExpenseListLoaded({
    required Month month,
    required this.currency,
    required this.days,
    required this.monthTotal,
    this.failure,
  }) : super(month);

  /// ISO 4217 code of the user's currency, for `formatMoney`.
  /// PT: Código ISO 4217 da moeda do usuário, para o `formatMoney`.
  final String currency;

  /// Newest day first; empty when the month has no expense.
  /// PT: Dia mais novo primeiro; vazio quando o mês não tem gasto.
  final List<ExpenseDayGroup> days;

  /// The sum of every expense of the month (equals the sum of the day totals).
  /// PT: A soma de todo gasto do mês (igual à soma dos totais dos dias).
  final Decimal monthTotal;

  /// A refresh that failed, kept typed next to the list that stays on screen.
  /// PT: Uma atualização que falhou, mantida tipada junto da lista que continua na tela.
  final ApiFailure? failure;

  bool get isEmpty => days.isEmpty;

  ExpenseListLoaded withFailure(ApiFailure? value) => ExpenseListLoaded(
    month: month,
    currency: currency,
    days: days,
    monthTotal: monthTotal,
    failure: value,
  );
}

final class ExpenseListFailed extends ExpenseListState {
  const ExpenseListFailed(super.month, this.failure);

  final ApiFailure failure;
}

/// Business state of the expense list: one month at a time, grouped by day, with exact totals.
/// PT: Estado de negócio da lista de gastos: um mês por vez, agrupado por dia, com totais exatos.
/// Notes: docs/code-notes/app-expenses.md#expenselistviewmodel
class ExpenseListViewModel extends ChangeNotifier {
  ExpenseListViewModel({required this._expenses, required this._users, required this._now}) {
    _month = Month.of(_now());
    _state = ExpenseListLoading(_month);
    _expenses.changes.addListener(_onExpensesChanged);
  }

  final ExpenseRepository _expenses;
  final UserRepository _users;
  final DateTime Function() _now;

  late Month _month;
  late ExpenseListState _state;
  String? _currency;
  int _ticket = 0;
  bool _disposed = false;

  ExpenseListState get state => _state;

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
    if (_state is! ExpenseListLoading || _state.month != _month) _emit(ExpenseListLoading(_month));
    final next = await _fetch(_month);
    // A newer load (another month, a retry) owns the screen now.
    // PT: Uma carga mais nova (outro mês, um retry) é dona da tela agora.
    if (ticket != _ticket) return;
    _emit(next);
  }

  /// Pull to refresh and reload after a write: the list stays on screen; a failure is kept next to it.
  /// PT: Puxar para atualizar e recarregar após uma escrita: a lista fica na tela; uma falha fica junto dela.
  Future<void> refresh() async {
    final current = _state;
    if (_disposed) return;
    if (current is! ExpenseListLoaded) return load();
    final ticket = ++_ticket;
    final next = await _fetch(_month);
    if (ticket != _ticket) return;
    _emit(switch (next) {
      ExpenseListFailed(:final failure) => current.withFailure(failure),
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

  // The list and the user's currency load together; the currency is asked once per screen.
  // PT: A lista e a moeda do usuário carregam juntas; a moeda é pedida uma vez por tela.
  Future<ExpenseListState> _fetch(Month month) async {
    try {
      final known = _currency;
      final results = await Future.wait<Object?>([
        _expenses.listMonth(month),
        if (known != null) Future.value(known) else _users.fetchCurrent().then((u) => u.currency),
      ]);
      final currency = results[1]! as String;
      _currency = currency;
      return _loaded(month, currency, results[0]! as List<ExpenseModel>);
    } on ApiFailure catch (failure) {
      return ExpenseListFailed(month, failure);
    }
  }

  ExpenseListLoaded _loaded(Month month, String currency, List<ExpenseModel> expenses) {
    final today = calendarDay(_now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    // Insertion order is the server's order (newest day first); equal days land in one group.
    // PT: A ordem de inserção é a do servidor (dia mais novo primeiro); dias iguais caem num só grupo.
    final byDay = <DateTime, List<ExpenseModel>>{};
    for (final expense in expenses) {
      (byDay[expense.date] ??= []).add(expense);
    }
    final days = [
      for (final MapEntry(key: date, value: items) in byDay.entries)
        ExpenseDayGroup(
          date: date,
          kind: date == today
              ? ExpenseDayKind.today
              : (date == yesterday ? ExpenseDayKind.yesterday : ExpenseDayKind.other),
          expenses: List.unmodifiable(items),
          total: _sum(items),
        ),
    ];
    return ExpenseListLoaded(
      month: month,
      currency: currency,
      days: List.unmodifiable(days),
      monthTotal: _sum(expenses),
    );
  }

  Decimal _sum(Iterable<ExpenseModel> items) =>
      items.fold(Decimal.zero, (sum, expense) => sum + expense.amount);

  void _onExpensesChanged() => unawaited(refresh());

  void _emit(ExpenseListState next) {
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

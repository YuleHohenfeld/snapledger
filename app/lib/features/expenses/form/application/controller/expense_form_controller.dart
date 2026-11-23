import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:snapledger/core/l10n/money_format.dart';
import 'package:snapledger/core/l10n/money_input.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/time/calendar_date.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/_shared/validation/category_validators.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_request.dart';
import 'package:snapledger/features/expenses/_shared/validation/expense_validators.dart';
import 'package:snapledger/features/expenses/form/application/viewmodel/expense_form_view_model.dart';

/// Screen-only state of the expense form (text fields, chosen date and category, field errors) and its events.
/// PT: Estado só da tela do formulário de gasto (campos de texto, data e categoria escolhidas, erros de campo) e seus eventos.
/// Notes: docs/code-notes/app-expenses.md#expenseformcontroller
class ExpenseFormController {
  /// [locale] is the device locale text (`pt_BR`): how the amount is typed and read. [now] is the clock.
  /// PT: [locale] é o texto do locale do aparelho (`pt_BR`): como o valor é digitado e lido. [now] é o relógio.
  ExpenseFormController({
    required this._viewModel,
    required this._navigator,
    required this._now,
    required this._locale,
  }) {
    _viewModel.addListener(_onViewModelChanged);
    _onViewModelChanged();
  }

  final ExpenseFormViewModel _viewModel;
  final AppNavigator _navigator;
  final DateTime Function() _now;
  final String _locale;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController amountField = TextEditingController();
  final FocusNode amountFocus = FocusNode();
  final TextEditingController descriptionField = TextEditingController();
  final FocusNode descriptionFocus = FocusNode();

  /// The category sheet's "New category" field and its form.
  /// PT: O campo "Nova categoria" da folha de categorias e o formulário dele.
  final GlobalKey<FormState> newCategoryFormKey = GlobalKey<FormState>();
  final TextEditingController newCategoryField = TextEditingController();
  final FocusNode newCategoryFocus = FocusNode();

  /// The chosen day (local midnight); null until the form is ready.
  /// PT: O dia escolhido (meia-noite local); nulo até o formulário estar pronto.
  final ValueNotifier<DateTime?> date = ValueNotifier(null);
  final ValueNotifier<CategoryModel?> category = ValueNotifier(null);

  /// Device-side errors of the two fields that are not text fields; cleared when the user changes them.
  /// PT: Erros no aparelho dos dois campos que não são de texto; limpos quando o usuário os muda.
  final ValueNotifier<ExpenseDateError?> dateError = ValueNotifier(null);
  final ValueNotifier<bool> categoryError = ValueNotifier(false);

  bool _filled = false;
  bool _disposed = false;

  /// The day picker's range: the API's limits.
  /// PT: O intervalo do seletor de dia: os limites da API.
  DateTime get firstDate => earliestExpenseDate;
  DateTime get lastDate => latestExpenseDate(_now());

  /// Where the day picker opens: the chosen day, else today.
  /// PT: Onde o seletor de dia abre: o dia escolhido, senão hoje.
  DateTime get pickerStart {
    // Kept inside the picker's range: it asserts when the start is outside it.
    // PT: Mantido dentro do intervalo do seletor: ele falha com uma assertion quando o início está fora.
    final start = date.value ?? calendarDay(_now());
    if (start.isBefore(firstDate)) return firstDate;
    return start.isAfter(lastDate) ? lastDate : start;
  }

  void start() => unawaited(_viewModel.load());

  void onRetryTapped() => unawaited(_viewModel.load());

  /// "Back" on the not-found screen.
  /// PT: "Voltar" na tela de não encontrado.
  void onBackTapped() => _navigator.pop();

  // Fills the fields once, when the form data arrives: the expense's values, or today for a new one.
  // PT: Preenche os campos uma vez, quando os dados do formulário chegam: os valores do gasto, ou hoje num novo.
  void _onViewModelChanged() {
    final state = _viewModel.state;
    if (_filled || state is! ExpenseFormEditing) return;
    _filled = true;
    final initial = state.initial;
    if (initial == null) {
      date.value = calendarDay(_now());
      return;
    }
    amountField.text = moneyInputText(
      initial.amount,
      locale: _locale,
      maxDecimals: _decimals(state.currency),
    );
    descriptionField.text = initial.description;
    date.value = initial.date;
    category.value = initial.category;
  }

  int _decimals(String currency) => moneyInputDigits(currency, locale: _locale);

  String? get _currency {
    final state = _viewModel.state;
    return state is ExpenseFormEditing ? state.currency : null;
  }

  ExpenseAmountError? amountError(String? value) {
    final currency = _currency;
    if (currency == null) return null;
    return validateExpenseAmount(value, locale: _locale, maxDecimals: _decimals(currency));
  }

  ExpenseDescriptionError? descriptionError(String? value) => validateExpenseDescription(value);

  CategoryNameError? categoryNameError(String? value) => validateCategoryName(value);

  /// The typed amount when it is valid and above zero, for the "will be saved as" preview; else null.
  /// PT: O valor digitado quando é válido e maior que zero, para a prévia "será salvo como"; senão null.
  Decimal? get previewAmount {
    final currency = _currency;
    if (currency == null || amountError(amountField.text) != null) return null;
    return parseMoneyInput(amountField.text, locale: _locale, maxDecimals: _decimals(currency));
  }

  /// The amount shown in the preview, formatted for the user's currency; null while there is nothing to show.
  /// PT: O valor mostrado na prévia, formatado na moeda do usuário; nulo enquanto não há o que mostrar.
  String? get previewText {
    final amount = previewAmount;
    final currency = _currency;
    if (amount == null || currency == null) return null;
    return formatMoney(amount, currency: currency, locale: _locale);
  }

  void onAmountEdited() => _viewModel.clearFieldError('amount');

  void onDescriptionEdited() => _viewModel.clearFieldError('description');

  /// The day picker closed: a null result means it was cancelled and changes nothing.
  /// PT: O seletor de dia fechou: resultado nulo significa cancelado e não muda nada.
  void onDatePicked(DateTime? picked) {
    if (picked == null) return;
    date.value = calendarDay(picked);
    dateError.value = null;
    _viewModel.clearFieldError('date');
  }

  /// A category row was tapped in the sheet.
  /// PT: Uma linha de categoria foi tocada na folha.
  void onCategoryPicked(CategoryModel picked) {
    category.value = picked;
    categoryError.value = false;
    _viewModel.clearFieldError('categoryId');
  }

  /// Creates the typed category and chooses it; null (and the field error) when the name is invalid or the API refused.
  /// PT: Cria a categoria digitada e a escolhe; nulo (e o erro no campo) quando o nome é inválido ou a API recusou.
  Future<CategoryModel?> onAddCategory() async {
    newCategoryFormKey.currentState?.validate();
    if (categoryNameError(newCategoryField.text) != null) return null;
    final created = await _viewModel.createCategory(newCategoryField.text);
    if (created == null || _disposed) return null;
    newCategoryField.clear();
    onCategoryPicked(created);
    return created;
  }

  /// Any edit of the new category name removes the old server error from the sheet.
  /// PT: Qualquer edição do nome da nova categoria tira da folha o erro antigo do servidor.
  void onNewCategoryEdited() => _viewModel.clearCategoryFailure();

  /// Shows every field error and stops when something is invalid; otherwise saves and leaves the screen.
  /// PT: Mostra todo erro de campo e para quando algo é inválido; senão salva e sai da tela.
  Future<void> onSubmit() async {
    formKey.currentState?.validate();
    final dateIssue = validateExpenseDate(date.value, now: _now());
    dateError.value = dateIssue;
    final chosen = category.value;
    categoryError.value = chosen == null;
    final currency = _currency;
    final amount = currency == null
        ? null
        : parseMoneyInput(amountField.text, locale: _locale, maxDecimals: _decimals(currency));
    if (amountError(amountField.text) != null ||
        descriptionError(descriptionField.text) != null ||
        dateIssue != null ||
        chosen == null ||
        amount == null) {
      return;
    }
    final saved = await _viewModel.save(
      ExpenseRequest(
        amount: amount,
        description: descriptionField.text.trim(),
        date: date.value!,
        categoryId: chosen.id,
      ),
    );
    if (saved && !_disposed) _navigator.pop();
  }

  /// The user confirmed the delete dialog.
  /// PT: O usuário confirmou o diálogo de apagar.
  Future<void> onDeleteConfirmed() async {
    final deleted = await _viewModel.delete();
    if (deleted && !_disposed) _navigator.pop();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _viewModel.removeListener(_onViewModelChanged);
    amountField.dispose();
    amountFocus.dispose();
    descriptionField.dispose();
    descriptionFocus.dispose();
    newCategoryField.dispose();
    newCategoryFocus.dispose();
    date.dispose();
    category.dispose();
    dateError.dispose();
    categoryError.dispose();
  }
}

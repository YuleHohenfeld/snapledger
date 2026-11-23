import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/features/categories/_shared/presentation/category_text.dart';
import 'package:snapledger/features/expenses/form/application/controller/expense_form_controller.dart';
import 'package:snapledger/features/expenses/form/application/viewmodel/expense_form_view_model.dart';
import 'package:snapledger/features/expenses/form/presentation/widgets/category_picker_sheet.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The category field: shows the chosen category and opens the picker sheet (own categories first).
/// PT: O campo de categoria: mostra a categoria escolhida e abre a folha de seleção (próprias primeiro).
/// Notes: docs/code-notes/app-expenses.md#categorypickersheet
class ExpenseCategoryField extends StatelessWidget {
  const ExpenseCategoryField({required this.controller, this.serverError, super.key});

  final ExpenseFormController controller;

  /// The text for a server `categoryId` error, or null.
  /// PT: O texto de um erro de `categoryId` do servidor, ou null.
  final String? serverError;

  Future<void> _open(BuildContext context) {
    // The sheet lives in the root overlay, outside this page's Provider: hand it the same ViewModel.
    // PT: A folha vive no overlay raiz, fora do Provider desta página: entregamos a ela o mesmo ViewModel.
    final viewModel = context.read<ExpenseFormViewModel>();
    controller.onCategorySheetOpened();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: viewModel,
        child: CategoryPickerSheet(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller.category, controller.categoryError]),
      builder: (context, _) {
        final category = controller.category.value;
        final hint = Theme.of(context).textTheme.bodyLarge
            ?.copyWith(color: Theme.of(context).hintColor);
        return Semantics(
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => unawaited(_open(context)),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.expenseFormCategoryLabel,
                suffixIcon: const Icon(Icons.expand_more),
                errorText: controller.categoryError.value
                    ? l10n.expenseFormCategoryRequired
                    : serverError,
              ),
              child: category == null
                  ? Text(l10n.expenseFormCategoryPlaceholder, style: hint)
                  : Text(categoryDisplayName(l10n, category)),
            ),
          ),
        );
      },
    );
  }
}

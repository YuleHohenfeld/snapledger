import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/app_text_field.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/design/widgets/gradient_button.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/_shared/presentation/category_text.dart';
import 'package:snapledger/features/expenses/form/application/controller/expense_form_controller.dart';
import 'package:snapledger/features/expenses/form/application/viewmodel/expense_form_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The bottom sheet that lists the categories (own first, then the defaults) and creates a new one on the spot.
/// PT: A folha que lista as categorias (próprias primeiro, depois as padrão) e cria uma nova na hora.
/// Notes: docs/code-notes/app-expenses.md#categorypickersheet
class CategoryPickerSheet extends StatelessWidget {
  const CategoryPickerSheet({required this.controller, super.key});

  final ExpenseFormController controller;

  static const _fields = {'name'};

  void _pick(BuildContext context, CategoryModel category) {
    controller.onCategoryPicked(category);
    // The sheet is a local overlay (not an app route), so it is closed here with its own context.
    // PT: A folha é uma camada local (não uma rota do app), então é fechada aqui com o próprio context.
    Navigator.of(context).pop();
  }

  Future<void> _add(BuildContext context) async {
    final created = await controller.onAddCategory();
    if (created != null && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.select((ExpenseFormViewModel vm) => vm.state);
    if (state is! ExpenseFormEditing) return const SizedBox.shrink();
    final failure = state.categoryFailure;
    final message = failureMessage(l10n, failure, knownFields: _fields);
    return Padding(
      // Lifts the sheet above the keyboard.
      // PT: Levanta a folha acima do teclado.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.m, AppSpacing.m, AppSpacing.s),
            child: Text(l10n.categoryPickerTitle, style: Theme.of(context).textTheme.titleMedium),
          ),
          Flexible(
            child: ValueListenableBuilder(
              valueListenable: controller.category,
              builder: (context, chosen, _) => ListView.builder(
                shrinkWrap: true,
                itemCount: state.categories.length,
                itemBuilder: (context, index) {
                  final category = state.categories[index];
                  final selected = category.id == chosen?.id;
                  return ListTile(
                    key: ValueKey(category.id),
                    selected: selected,
                    title: Text(categoryDisplayName(l10n, category)),
                    trailing: selected ? const Icon(Icons.check) : null,
                    onTap: () => _pick(context, category),
                  );
                },
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Form(
              key: controller.newCategoryFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message != null) ...[
                    FormErrorBanner(message: message),
                    const SizedBox(height: AppSpacing.m),
                  ],
                  AppTextField(
                    controller: controller.newCategoryField,
                    focusNode: controller.newCategoryFocus,
                    label: l10n.categoryPickerNewLabel,
                    validator: (value) =>
                        categoryNameErrorText(l10n, controller.categoryNameError(value)),
                    errorText: fieldErrorMessage(l10n, failure, 'name'),
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => controller.onNewCategoryEdited(),
                    onFieldSubmitted: (_) {
                      if (!state.creatingCategory) unawaited(_add(context));
                    },
                  ),
                  const SizedBox(height: AppSpacing.m),
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      label: l10n.categoryPickerAdd,
                      busy: state.creatingCategory,
                      onPressed: () => unawaited(_add(context)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

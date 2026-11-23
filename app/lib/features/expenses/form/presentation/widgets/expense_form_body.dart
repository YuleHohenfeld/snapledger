import 'dart:async';

import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/app_text_field.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/design/widgets/gradient_button.dart';
import 'package:snapledger/core/design/widgets/money_field.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/expenses/_shared/presentation/expense_text.dart';
import 'package:snapledger/features/expenses/form/application/controller/expense_form_controller.dart';
import 'package:snapledger/features/expenses/form/application/viewmodel/expense_form_view_model.dart';
import 'package:snapledger/features/expenses/form/presentation/widgets/amount_preview.dart';
import 'package:snapledger/features/expenses/form/presentation/widgets/expense_category_field.dart';
import 'package:snapledger/features/expenses/form/presentation/widgets/expense_date_field.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The form itself: amount (with its preview), description, date, category and the save button.
/// PT: O formulário em si: valor (com a prévia), descrição, data, categoria e o botão de salvar.
/// Notes: docs/code-notes/app-expenses.md#expenseformpage
class ExpenseFormBody extends StatelessWidget {
  const ExpenseFormBody({required this.state, required this.controller, super.key});

  final ExpenseFormEditing state;
  final ExpenseFormController controller;

  // Field names of the contract's ExpenseRequest, as `fieldErrors` carries them.
  // PT: Nomes dos campos do ExpenseRequest do contrato, como o `fieldErrors` os traz.
  static const _fields = {'amount', 'description', 'date', 'categoryId'};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final failure = state.failure;
    final message = failureMessage(l10n, failure, knownFields: _fields);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Form(
        key: controller.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message != null) ...[
              FormErrorBanner(message: message),
              const SizedBox(height: AppSpacing.m),
            ],
            MoneyField(
              controller: controller.amountField,
              focusNode: controller.amountFocus,
              label: l10n.expenseFormAmountLabel,
              currency: state.currency,
              validator: (value) => expenseAmountErrorText(l10n, controller.amountError(value)),
              errorText: fieldErrorMessage(l10n, failure, 'amount'),
              autofocus: state.initial == null,
              textInputAction: TextInputAction.next,
              onChanged: (_) => controller.onAmountEdited(),
            ),
            AmountPreview(controller: controller),
            const SizedBox(height: AppSpacing.m),
            AppTextField(
              controller: controller.descriptionField,
              focusNode: controller.descriptionFocus,
              label: l10n.expenseFormDescriptionLabel,
              validator: (value) =>
                  expenseDescriptionErrorText(l10n, controller.descriptionError(value)),
              errorText: fieldErrorMessage(l10n, failure, 'description'),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onChanged: (_) => controller.onDescriptionEdited(),
            ),
            const SizedBox(height: AppSpacing.m),
            ExpenseDateField(
              controller: controller,
              serverError: fieldErrorMessage(l10n, failure, 'date'),
            ),
            const SizedBox(height: AppSpacing.m),
            ExpenseCategoryField(
              controller: controller,
              serverError: fieldErrorMessage(l10n, failure, 'categoryId'),
            ),
            const SizedBox(height: AppSpacing.l),
            GradientButton(
              label: l10n.expenseFormSave,
              busy: state.saving,
              onPressed: () => unawaited(controller.onSubmit()),
            ),
          ],
        ),
      ),
    );
  }
}

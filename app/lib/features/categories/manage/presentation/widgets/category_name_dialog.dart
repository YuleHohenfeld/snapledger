import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/app_text_field.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/design/widgets/gradient_button.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/categories/_shared/presentation/category_text.dart';
import 'package:snapledger/features/categories/manage/application/controller/category_manage_controller.dart';
import 'package:snapledger/features/categories/manage/application/viewmodel/category_manage_view_model.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The dialog that asks for a category name (create or rename); it closes itself only when the save worked.
/// PT: O diálogo que pede o nome de uma categoria (criar ou renomear); só fecha sozinho quando o salvar deu certo.
/// Notes: docs/code-notes/app-categories.md#categorymanagepage
class CategoryNameDialog extends StatelessWidget {
  const CategoryNameDialog({required this.controller, super.key});

  final CategoryManageController controller;

  static const _fields = {'name'};

  /// Fixed width so the button does not jump when its spinner replaces the label.
  /// PT: Largura fixa para o botão não pular quando o spinner substitui o rótulo.
  static const _saveButtonWidth = 140.0;

  Future<void> _save(BuildContext context) async {
    final saved = await controller.onSaveName();
    // The dialog is a local overlay (not an app route), so it is closed here with its own context.
    // PT: O diálogo é uma camada local (não uma rota do app), então é fechado aqui com o próprio context.
    if (saved && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loaded = context.select((CategoryManageViewModel vm) => vm.state);
    final busy = loaded is CategoryManageLoaded && loaded.busy;
    final failure = loaded is CategoryManageLoaded ? loaded.failure : null;
    final formMessage = failureMessage(l10n, failure, knownFields: _fields);
    return AlertDialog(
      title: Text(
        controller.isRenaming ? l10n.categoryManageRenameTitle : l10n.categoryManageCreateTitle,
      ),
      content: Form(
        key: controller.formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (formMessage != null) ...[
              FormErrorBanner(message: formMessage),
              const SizedBox(height: AppSpacing.m),
            ],
            AppTextField(
              controller: controller.nameField,
              focusNode: controller.nameFocus,
              label: l10n.categoryManageNameLabel,
              validator: (value) => categoryNameErrorText(l10n, controller.nameError(value)),
              errorText: fieldErrorMessage(l10n, failure, 'name'),
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onChanged: (_) => controller.onNameEdited(),
              onFieldSubmitted: (_) {
                if (!busy) unawaited(_save(context));
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.categoryManageCancel),
        ),
        SizedBox(
          width: _saveButtonWidth,
          child: GradientButton(
            label: l10n.categoryManageSave,
            busy: busy,
            onPressed: () => unawaited(_save(context)),
          ),
        ),
      ],
    );
  }
}

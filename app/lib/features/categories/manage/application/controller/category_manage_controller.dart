import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/_shared/validation/category_validators.dart';
import 'package:snapledger/features/categories/manage/application/viewmodel/category_manage_view_model.dart';

/// Screen-only state of the name dialog (text, form key, which category is being renamed) and the user events.
/// PT: Estado só da tela do diálogo de nome (texto, form key, qual categoria está sendo renomeada) e os eventos.
/// Notes: docs/code-notes/app-categories.md#categorymanagecontroller
class CategoryManageController {
  CategoryManageController({required this._viewModel});

  final CategoryManageViewModel _viewModel;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController nameField = TextEditingController();
  final FocusNode nameFocus = FocusNode();

  // Null while creating; the category being renamed otherwise.
  // PT: Nulo ao criar; a categoria sendo renomeada nos outros casos.
  CategoryModel? _renaming;

  /// Whether the open dialog renames a category (true) or creates one (false).
  /// PT: Se o diálogo aberto renomeia uma categoria (true) ou cria uma (false).
  bool get isRenaming => _renaming != null;

  void start() => unawaited(_viewModel.load());

  void onRetryTapped() => unawaited(_viewModel.load());

  Future<void> onRefresh() => _viewModel.refresh();

  /// Prepares an empty dialog.
  /// PT: Prepara um diálogo vazio.
  void beginCreate() {
    _renaming = null;
    nameField.clear();
    _viewModel.clearFailure();
  }

  /// Prepares the dialog with the current name of [category].
  /// PT: Prepara o diálogo com o nome atual de [category].
  void beginRename(CategoryModel category) {
    _renaming = category;
    nameField.text = category.name;
    _viewModel.clearFailure();
  }

  CategoryNameError? nameError(String? value) => validateCategoryName(value);

  /// Any edit of the name removes the old server error from the screen.
  /// PT: Qualquer edição do nome tira da tela o erro antigo do servidor.
  void onNameEdited() => _viewModel.clearFailure();

  /// The name dialog closed (saved or cancelled): a cancelled attempt leaves no old error behind.
  /// PT: O diálogo de nome fechou (salvo ou cancelado): uma tentativa cancelada não deixa erro antigo para trás.
  void onDialogClosed() => _viewModel.clearFailure();

  /// Shows the field error and stops when the name is invalid; otherwise saves. True means: close the dialog.
  /// PT: Mostra o erro do campo e para quando o nome é inválido; senão salva. True significa: feche o diálogo.
  Future<bool> onSaveName() async {
    formKey.currentState?.validate();
    if (nameError(nameField.text) != null) return false;
    final renaming = _renaming;
    return renaming == null
        ? _viewModel.create(nameField.text)
        : _viewModel.rename(renaming.id, nameField.text);
  }

  /// The user confirmed the delete dialog.
  /// PT: O usuário confirmou o diálogo de apagar.
  Future<void> onDeleteConfirmed(CategoryModel category) => _viewModel.delete(category.id);

  void dispose() {
    nameField.dispose();
    nameFocus.dispose();
  }
}

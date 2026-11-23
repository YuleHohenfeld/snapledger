import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/manage/application/controller/category_manage_controller.dart';
import 'package:snapledger/features/categories/manage/application/viewmodel/category_manage_view_model.dart';
import 'package:snapledger/features/categories/manage/presentation/widgets/category_list.dart';
import 'package:snapledger/features/categories/manage/presentation/widgets/category_load_error.dart';
import 'package:snapledger/features/categories/manage/presentation/widgets/category_name_dialog.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Profile > Categories: the default categories (locked) and the user's own, with add, rename and delete.
/// PT: Perfil > Categorias: as categorias padrão (travadas) e as do usuário, com adicionar, renomear e apagar.
/// Notes: docs/code-notes/app-categories.md#categorymanagepage
class CategoryManagePage extends StatelessWidget {
  const CategoryManagePage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) => CategoryManageViewModel(categories: context.read()),
    child: const _CategoryManageView(),
  );
}

class _CategoryManageView extends StatefulWidget {
  const _CategoryManageView();

  @override
  State<_CategoryManageView> createState() => _CategoryManageViewState();
}

class _CategoryManageViewState extends State<_CategoryManageView> {
  late final CategoryManageController _controller;

  static const _maxWidth = 560.0;

  @override
  void initState() {
    super.initState();
    _controller = CategoryManageController(viewModel: context.read<CategoryManageViewModel>())
      ..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _showNameDialog() async {
    // The dialog lives in the root overlay, outside this page's Provider: hand it the same ViewModel.
    // PT: O diálogo vive no overlay raiz, fora do Provider desta página: entregamos a ele o mesmo ViewModel.
    final viewModel = context.read<CategoryManageViewModel>();
    await showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: viewModel,
        child: CategoryNameDialog(controller: _controller),
      ),
    );
    _controller.onDialogClosed();
  }

  void _onAdd() {
    _controller.beginCreate();
    unawaited(_showNameDialog());
  }

  void _onRename(CategoryModel category) {
    _controller.beginRename(category);
    unawaited(_showNameDialog());
  }

  Future<void> _onDelete(CategoryModel category) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.categoryManageDeleteTitle),
        content: Text(l10n.categoryManageDeleteBody(category.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.categoryManageCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.categoryManageDelete),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _controller.onDeleteConfirmed(category);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.select((CategoryManageViewModel vm) => vm.state);
    final busy = state is CategoryManageLoaded && state.busy;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.categoryManageTitle)),
      floatingActionButton: state is CategoryManageLoaded
          ? FloatingActionButton.extended(
              onPressed: busy ? null : _onAdd,
              icon: const Icon(Icons.add),
              label: Text(l10n.categoryManageAdd),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: switch (state) {
              CategoryManageLoading() => const Center(child: CircularProgressIndicator()),
              CategoryManageFailed(:final failure) => CategoryLoadError(
                failure: failure,
                onRetry: _controller.onRetryTapped,
              ),
              CategoryManageLoaded() => CategoryList(
                state: state,
                onRefresh: _controller.onRefresh,
                onRename: _onRename,
                onDelete: (category) => unawaited(_onDelete(category)),
              ),
            },
          ),
        ),
      ),
    );
  }
}

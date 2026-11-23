import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/manage/application/viewmodel/category_manage_view_model.dart';
import 'package:snapledger/features/categories/manage/presentation/widgets/category_tile.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The loaded list: the user's own categories first, then the locked defaults, with pull to refresh.
/// PT: A lista carregada: primeiro as categorias do usuário, depois as padrão travadas, com puxar para atualizar.
/// Notes: docs/code-notes/app-categories.md#categorymanagepage
class CategoryList extends StatelessWidget {
  const CategoryList({
    required this.state,
    required this.onRefresh,
    required this.onRename,
    required this.onDelete,
    super.key,
  });

  final CategoryManageLoaded state;
  final Future<void> Function() onRefresh;
  final ValueChanged<CategoryModel> onRename;
  final ValueChanged<CategoryModel> onDelete;

  /// Room under the last row so the floating button does not cover it.
  /// PT: Espaço sob a última linha para o botão flutuante não cobri-la.
  static const _bottomClearance = 88.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = failureMessage(l10n, state.failure, knownFields: const {'name'});
    final headerStyle = Theme.of(context).textTheme.titleSmall;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.m,
          AppSpacing.m,
          AppSpacing.m,
          _bottomClearance,
        ),
        children: [
          if (message != null) ...[
            FormErrorBanner(message: message),
            const SizedBox(height: AppSpacing.m),
          ],
          Text(l10n.categoryManageOwnHeader, style: headerStyle),
          if (state.own.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
              child: Text(l10n.categoryManageOwnEmpty),
            ),
          for (final category in state.own)
            CategoryTile(
              key: ValueKey(category.id),
              category: category,
              enabled: !state.busy,
              onRename: () => onRename(category),
              onDelete: () => onDelete(category),
            ),
          const SizedBox(height: AppSpacing.l),
          Text(l10n.categoryManageDefaultsHeader, style: headerStyle),
          for (final category in state.defaults)
            CategoryTile(key: ValueKey(category.id), category: category, enabled: false),
        ],
      ),
    );
  }
}

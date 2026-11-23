import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_colors.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/glass_panel.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/_shared/presentation/category_text.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

enum _CategoryAction { rename, delete }

/// One row: a default shows a lock and says it cannot be changed; an own one has a rename / delete menu.
/// PT: Uma linha: a padrão mostra um cadeado e diz que não pode ser alterada; a própria tem menu de renomear / apagar.
/// Notes: docs/code-notes/app-categories.md#categorymanagepage
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    required this.category,
    required this.enabled,
    super.key,
    this.onRename,
    this.onDelete,
  });

  final CategoryModel category;

  /// False while a write is running, so the menu cannot start a second one.
  /// PT: Falso enquanto uma escrita roda, para o menu não iniciar uma segunda.
  final bool enabled;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = categoryDisplayName(l10n, category);
    final Widget row;
    if (category.isDefault) {
      row = Semantics(
        label: l10n.categoryManageDefaultLocked(name),
        excludeSemantics: true,
        child: ListTile(title: Text(name), trailing: const Icon(Icons.lock_outline)),
      );
    } else {
      row = ListTile(
        title: Text(name),
        trailing: PopupMenuButton<_CategoryAction>(
          tooltip: l10n.categoryManageActionsFor(name),
          enabled: enabled,
          onSelected: (action) => switch (action) {
            _CategoryAction.rename => onRename?.call(),
            _CategoryAction.delete => onDelete?.call(),
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: _CategoryAction.rename, child: Text(l10n.categoryManageRename)),
            PopupMenuItem(value: _CategoryAction.delete, child: Text(l10n.categoryManageDelete)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: GlassPanel(radius: AppGlass.rowRadius, child: row),
    );
  }
}

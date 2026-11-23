import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/_shared/validation/category_validators.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The name to show: a default is translated from its `key`; an own name (or an unknown key) shows as sent.
/// PT: O nome a mostrar: uma padrão é traduzida pelo `key`; um nome próprio (ou key desconhecida) aparece como veio.
/// Notes: docs/code-notes/app-categories.md#categorydisplayname
String categoryDisplayName(AppLocalizations l10n, CategoryModel category) {
  if (!category.isDefault) return category.name;
  return switch (category.key) {
    'food' => l10n.categoryDefaultFood,
    'groceries' => l10n.categoryDefaultGroceries,
    'transport' => l10n.categoryDefaultTransport,
    'housing' => l10n.categoryDefaultHousing,
    'health' => l10n.categoryDefaultHealth,
    'leisure' => l10n.categoryDefaultLeisure,
    'education' => l10n.categoryDefaultEducation,
    'other' => l10n.categoryDefaultOther,
    _ => category.name,
  };
}

/// The localized text of a device-side category name error, or null when the name is valid.
/// PT: O texto traduzido de um erro de nome de categoria detectado no aparelho, ou null quando o nome é válido.
String? categoryNameErrorText(AppLocalizations l10n, CategoryNameError? error) => switch (error) {
  null => null,
  CategoryNameError.required => l10n.validationRequired,
  CategoryNameError.tooLong => l10n.validationNameTooLong(categoryNameMaxCodePoints),
  CategoryNameError.invalidChars => l10n.validationNameInvalidChars,
};

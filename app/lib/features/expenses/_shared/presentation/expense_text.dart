import 'package:snapledger/features/expenses/_shared/validation/expense_validators.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The localized text of a device-side amount error, or null when the amount is valid.
/// PT: O texto traduzido de um erro de valor detectado no aparelho, ou null quando o valor é válido.
String? expenseAmountErrorText(AppLocalizations l10n, ExpenseAmountError? error) => switch (error) {
  null => null,
  ExpenseAmountError.required => l10n.validationRequired,
  ExpenseAmountError.invalid => l10n.expenseFormAmountInvalid,
  ExpenseAmountError.notPositive => l10n.expenseFormAmountNotPositive,
  ExpenseAmountError.tooLarge => l10n.expenseFormAmountTooLarge,
};

/// The localized text of a device-side description error, or null when it is valid.
/// PT: O texto traduzido de um erro de descrição detectado no aparelho, ou null quando é válida.
String? expenseDescriptionErrorText(AppLocalizations l10n, ExpenseDescriptionError? error) =>
    switch (error) {
      null => null,
      ExpenseDescriptionError.required => l10n.validationRequired,
      ExpenseDescriptionError.tooLong => l10n.expenseFormDescriptionTooLong(
        expenseDescriptionMaxCodePoints,
      ),
      ExpenseDescriptionError.invalidChars => l10n.expenseFormDescriptionInvalidChars,
    };

/// The localized text of a device-side date error, or null when the date is valid.
/// PT: O texto traduzido de um erro de data detectado no aparelho, ou null quando a data é válida.
String? expenseDateErrorText(AppLocalizations l10n, ExpenseDateError? error) => switch (error) {
  null => null,
  ExpenseDateError.required => l10n.validationRequired,
  ExpenseDateError.tooOld => l10n.expenseFormDateTooOld,
  ExpenseDateError.tooFarAhead => l10n.expenseFormDateTooFar,
};

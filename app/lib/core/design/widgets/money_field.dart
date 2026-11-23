import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/number_symbols.dart';
import 'package:snapledger/core/design/widgets/app_text_field.dart';
import 'package:snapledger/core/l10n/money_format.dart';
import 'package:snapledger/core/l10n/money_input.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The amount field: the currency symbol as prefix, a decimal keyboard and a formatter that only lets
/// digits and one decimal separator of the locale in. The text is turned into a Decimal by [parseMoneyInput].
/// PT: O campo de valor: símbolo da moeda como prefixo, teclado decimal e um formatador que só deixa entrar
/// dígitos e um separador decimal do locale. O texto vira Decimal pelo [parseMoneyInput].
/// Notes: docs/code-notes/app-core.md#money
class MoneyField extends StatelessWidget {
  const MoneyField({
    required this.controller,
    required this.label,
    required this.currency,
    super.key,
    this.focusNode,
    this.validator,
    this.errorText,
    this.textInputAction,
    this.autofocus = false,
    this.onFieldSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;

  /// ISO 4217 code of the user's currency; decides the symbol and how many decimals are accepted.
  /// PT: Código ISO 4217 da moeda do usuário; decide o símbolo e quantas casas decimais são aceitas.
  final String currency;
  final FocusNode? focusNode;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final digits = moneyInputDigits(currency, locale: locale);
    return Semantics(
      hint: AppLocalizations.of(context).moneyFieldCurrencyHint(currency),
      child: AppTextField(
        controller: controller,
        label: label,
        focusNode: focusNode,
        validator: validator,
        errorText: errorText,
        prefixText: '${currencySymbol(currency, locale: locale)} ',
        keyboardType: TextInputType.numberWithOptions(decimal: digits > 0),
        inputFormatters: [MoneyInputFormatter(locale: locale, decimals: digits)],
        textInputAction: textInputAction,
        autofocus: autofocus,
        autocorrect: false,
        enableSuggestions: false,
        onFieldSubmitted: onFieldSubmitted,
        onChanged: onChanged,
      ),
    );
  }
}

/// Never edits characters silently: a typed key is accepted, turned into the locale's decimal separator
/// (`.` or `,`) or rejected; a paste is accepted only if [parseMoneyInput] accepts it, else it is refused.
/// PT: Nunca altera caracteres em silêncio: tecla digitada é aceita, vira o separador decimal do locale
/// PT: (`.` ou `,`) ou é rejeitada; colagem só passa se o [parseMoneyInput] aceitar, senão é recusada.
/// Notes: docs/code-notes/app-core.md#money
class MoneyInputFormatter extends TextInputFormatter {
  MoneyInputFormatter({required this.locale, required this.decimals})
    : _symbols = NumberFormat.decimalPattern(locale).symbols;

  final String locale;
  final int decimals;
  final NumberSymbols _symbols;

  String get _separator => _symbols.DECIMAL_SEP;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final old = oldValue.text;
    final text = newValue.text;
    if (text == old) return newValue;
    if (text.length == old.length + 1) return _typedKey(oldValue, newValue);
    // Deleting or retyping with only canonical characters needs no interpretation.
    // PT: Apagar ou redigitar só com caracteres canônicos não precisa de interpretação.
    if (_isCanonical(text)) return newValue;
    // Anything else is a paste: the same parser as the submit decides; never strip characters.
    // PT: Qualquer outra coisa é colagem: o mesmo parser do envio decide; nunca remove caracteres.
    if (parseMoneyInput(text, locale: locale, maxDecimals: decimals) == null) return oldValue;
    final canonical = text.trim().replaceAll(_symbols.GROUP_SEP, '');
    return TextEditingValue(text: canonical, selection: TextSelection.collapsed(offset: canonical.length));
  }

  TextEditingValue _typedKey(TextEditingValue oldValue, TextEditingValue newValue) {
    final old = oldValue.text;
    final text = newValue.text;
    var at = 0;
    while (at < old.length && old[at] == text[at]) {
      at++;
    }
    final key = text[at];
    if (_isDigit(key)) return _isCanonical(text) ? newValue : oldValue;
    if (key != '.' && key != ',') return oldValue;
    // The user meant "decimal": write the locale's separator (the iOS keypad may only offer `.`).
    // PT: O usuário quis dizer "decimal": escreve o separador do locale (o teclado do iOS pode só ter `.`).
    if (decimals == 0 || old.contains(_separator)) return oldValue;
    final fixed = text.replaceRange(at, at + 1, _separator);
    return _isCanonical(fixed) ? newValue.copyWith(text: fixed) : oldValue;
  }

  /// Only ASCII digits, at most one separator and at most [decimals] places after it.
  bool _isCanonical(String text) {
    final parts = text.split(_separator);
    if (parts.length > 2 || (parts.length == 2 && decimals == 0)) return false;
    if (parts.length == 2 && parts[1].length > decimals) return false;
    return parts.every((part) => part.split('').every(_isDigit));
  }

  bool _isDigit(String char) => char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;
}

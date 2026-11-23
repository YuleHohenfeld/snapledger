import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:snapledger/core/design/widgets/clears_error_on_edit.dart';

/// A labeled form text field; [errorText] (from the server) shows only while [validator] passes.
/// PT: Um campo de texto de formulário com rótulo; [errorText] (do servidor) aparece só enquanto o [validator] passa.
/// Its validator message disappears on the first edit (see [ClearsErrorOnEdit]).
/// PT: A mensagem do validator some na primeira edição (veja [ClearsErrorOnEdit]).
/// Notes: docs/code-notes/app-auth.md#design-widgets
class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.controller,
    required this.label,
    super.key,
    this.focusNode,
    this.validator,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.prefixText,
    this.inputFormatters,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.autofocus = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.textCapitalization = TextCapitalization.none,
    this.onFieldSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final String? helperText;
  final IconData? prefixIcon;

  /// Text shown before the typed value, such as a currency symbol.
  /// PT: Texto mostrado antes do valor digitado, como um símbolo de moeda.
  final String? prefixText;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool autofocus;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> with ClearsErrorOnEdit<AppTextField> {
  @override
  Widget build(BuildContext context) => TextFormField(
    key: fieldKey,
    controller: widget.controller,
    focusNode: widget.focusNode,
    validator: wrapValidator(widget.validator),
    keyboardType: widget.keyboardType,
    inputFormatters: widget.inputFormatters,
    textInputAction: widget.textInputAction,
    autofillHints: widget.autofillHints,
    autofocus: widget.autofocus,
    autocorrect: widget.autocorrect,
    enableSuggestions: widget.enableSuggestions,
    textCapitalization: widget.textCapitalization,
    onFieldSubmitted: widget.onFieldSubmitted,
    onChanged: (value) {
      clearErrorOnEdit();
      widget.onChanged?.call(value);
    },
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helperText,
      errorText: widget.errorText,
      prefixText: widget.prefixText,
      prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
    ),
  );
}

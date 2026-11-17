import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:snapledger/core/design/widgets/clears_error_on_edit.dart';

/// The field for a 6-digit code from an email: digits only, numeric keyboard, one-time-code autofill.
/// PT: O campo do código de 6 dígitos recebido por email: só dígitos, teclado numérico, autofill de código único.
/// Its error disappears on the first edit (see [ClearsErrorOnEdit]); it holds no logic beyond typing.
/// PT: O erro some na primeira edição (veja [ClearsErrorOnEdit]); não tem lógica além da digitação.
/// Notes: docs/code-notes/app-auth.md#codefield
class CodeField extends StatefulWidget {
  const CodeField({
    required this.controller,
    required this.label,
    super.key,
    this.focusNode,
    this.validator,
    this.errorText,
    this.textInputAction,
    this.onFieldSubmitted,
    this.onChanged,
  });

  /// Number of digits of every code in the contract.
  /// PT: Quantidade de dígitos de todo código do contrato.
  static const length = 6;

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField> with ClearsErrorOnEdit<CodeField> {
  @override
  Widget build(BuildContext context) => TextFormField(
    key: fieldKey,
    controller: widget.controller,
    focusNode: widget.focusNode,
    validator: wrapValidator(widget.validator),
    keyboardType: TextInputType.number,
    textInputAction: widget.textInputAction,
    autofillHints: const [AutofillHints.oneTimeCode],
    autocorrect: false,
    enableSuggestions: false,
    maxLength: CodeField.length,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: 4),
    onFieldSubmitted: widget.onFieldSubmitted,
    onChanged: (value) {
      clearErrorOnEdit();
      widget.onChanged?.call(value);
    },
    decoration: InputDecoration(
      labelText: widget.label,
      errorText: widget.errorText,
      // The length is in the label and the formatter; the counter would only add noise.
      // PT: O tamanho está no rótulo e no formatter; o contador só atrapalharia.
      counterText: '',
      prefixIcon: const Icon(Icons.pin_outlined),
    ),
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:snapledger/core/design/widgets/clears_error_on_edit.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// A password field hidden by default, with a show/hide button and no autocorrect or suggestions.
/// PT: Um campo de senha oculto por padrão, com botão mostrar/ocultar e sem autocorreção nem sugestões.
/// Its validator message disappears on the first edit (see [ClearsErrorOnEdit]).
/// PT: A mensagem do validator some na primeira edição (veja [ClearsErrorOnEdit]).
/// Notes: docs/code-notes/app-auth.md#design-widgets
class PasswordField extends StatefulWidget {
  const PasswordField({
    required this.controller,
    required this.label,
    required this.visible,
    required this.onToggleVisibility,
    required this.autofillHints,
    super.key,
    this.focusNode,
    this.validator,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.textInputAction,
    this.autofocus = false,
    this.onFieldSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;

  /// Whether the text is shown; owned by the screen's Controller.
  /// PT: Se o texto está visível; pertence ao Controller da tela.
  final ValueListenable<bool> visible;
  final VoidCallback onToggleVisibility;

  /// `AutofillHints.password` on login, `AutofillHints.newPassword` on register.
  /// PT: `AutofillHints.password` no login, `AutofillHints.newPassword` no cadastro.
  final Iterable<String> autofillHints;
  final FocusNode? focusNode;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final String? helperText;
  final IconData? prefixIcon;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> with ClearsErrorOnEdit<PasswordField> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: widget.visible,
      builder: (context, shown, _) => TextFormField(
        key: fieldKey,
        controller: widget.controller,
        focusNode: widget.focusNode,
        validator: wrapValidator(widget.validator),
        obscureText: !shown,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: widget.textInputAction,
        autofillHints: widget.autofillHints,
        autofocus: widget.autofocus,
        onFieldSubmitted: widget.onFieldSubmitted,
        onChanged: (value) {
          clearErrorOnEdit();
          widget.onChanged?.call(value);
        },
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          errorText: widget.errorText,
          prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
          suffixIcon: IconButton(
            onPressed: widget.onToggleVisibility,
            tooltip: shown ? l10n.passwordHide : l10n.passwordShow,
            icon: Icon(shown ? Icons.visibility_off : Icons.visibility),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Makes a [TextFormField]'s validator message vanish as soon as the user edits it; the next
/// `Form.validate()` (submit) checks the field again. Never touches the text.
/// PT: Faz a mensagem do validator de um [TextFormField] sumir assim que o usuário edita; o próximo
/// `Form.validate()` (envio) confere o campo de novo. Nunca mexe no texto.
/// Notes: docs/code-notes/app-auth.md#design-widgets
mixin ClearsErrorOnEdit<T extends StatefulWidget> on State<T> {
  /// Give this to the field's `key`.
  /// PT: Passe isto ao `key` do campo.
  final fieldKey = GlobalKey<FormFieldState<String>>();

  bool _suppress = false;

  /// Wraps the screen's validator so the edit can silence it for one call.
  /// PT: Envolve o validator da tela para a edição poder silenciá-lo por uma chamada.
  FormFieldValidator<String>? wrapValidator(
    FormFieldValidator<String>? validator,
  ) {
    if (validator == null) return null;
    return (value) => _suppress ? null : validator(value);
  }

  /// Call from `onChanged`: re-runs the (silenced) validation only when an error is on screen.
  /// PT: Chame no `onChanged`: roda a validação (silenciada) só quando há um erro na tela.
  void clearErrorOnEdit() {
    final field = fieldKey.currentState;
    if (field == null || !field.hasError) return;
    _suppress = true;
    try {
      field.validate();
    } finally {
      _suppress = false;
    }
  }
}

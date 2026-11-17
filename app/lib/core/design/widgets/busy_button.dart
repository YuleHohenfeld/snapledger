import 'package:flutter/material.dart';

/// A filled button that is disabled and shows a spinner while [busy], so it cannot be tapped twice.
/// PT: Um botão preenchido que fica desativado e mostra um spinner enquanto [busy], para não ser tocado duas vezes.
/// Notes: docs/code-notes/app-auth.md#design-widgets
class BusyButton extends StatelessWidget {
  const BusyButton({required this.label, required this.busy, required this.onPressed, super.key});

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  static const _spinnerSize = 20.0;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    child: busy
        ? Semantics(
            label: label,
            child: const SizedBox.square(
              dimension: _spinnerSize,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : Text(label),
  );
}

import 'package:flutter/material.dart';

/// Centers [child] and limits its width to [maxWidth], so text lines are not stretched across a wide window.
/// PT: Centraliza [child] e limita a largura a [maxWidth], para as linhas de texto não esticarem numa janela larga.
/// Notes: docs/code-notes/app-core.md#responsive-shell
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({required this.maxWidth, required this.child, super.key});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

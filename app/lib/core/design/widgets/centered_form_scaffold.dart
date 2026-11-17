import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// A full-screen page (no app bar) with a scrollable form centered at a readable width (phone, tablet, web).
/// PT: Uma página em tela cheia (sem app bar) com um formulário rolável centralizado numa largura legível (celular, tablet, web).
/// Notes: docs/code-notes/app-auth.md#design-widgets
class CenteredFormScaffold extends StatelessWidget {
  const CenteredFormScaffold({required this.child, super.key});

  final Widget child;

  static const _maxFormWidth = 420.0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxFormWidth),
            child: child,
          ),
        ),
      ),
    ),
  );
}

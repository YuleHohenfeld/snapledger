import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// An auth page: optional back arrow, 24 dp side padding, a form centered at a readable width, and an
/// optional [footer] pinned to the bottom (it scrolls with the form only when the screen is too short).
/// PT: Uma página de auth: seta de voltar opcional, 24 dp nas laterais, um formulário centralizado numa largura
/// legível e um [footer] opcional fixo no fim (rola junto com o formulário só quando a tela é baixa demais).
/// Notes: docs/code-notes/app-auth.md#design-widgets
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.child, super.key, this.footer, this.onBack});

  final Widget child;
  final Widget? footer;

  /// When set, the app bar (back arrow only, no title) appears; secondary screens use it.
  /// PT: Quando definido, a app bar (só a seta, sem título) aparece; as telas secundárias a usam.
  final VoidCallback? onBack;

  static const _maxFormWidth = 420.0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: onBack == null
        ? null
        : AppBar(
            leading: BackButton(onPressed: onBack),
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
          ),
    body: SafeArea(
      // No intrinsic sizes: the column is at least as tall as the viewport, and `spaceBetween` pushes
      // the footer down; a taller form just scrolls.
      // PT: Sem tamanhos intrínsecos: a coluna tem pelo menos a altura da viewport, e o `spaceBetween` empurra
      // o rodapé para baixo; um formulário mais alto apenas rola.
      child: LayoutBuilder(
        builder: (context, viewport) => SingleChildScrollView(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: viewport.maxHeight,
                maxWidth: _maxFormWidth + 2 * AppSpacing.l,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.l,
                  AppSpacing.m,
                  AppSpacing.l,
                  AppSpacing.s,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    child,
                    if (footer != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.m),
                        child: footer,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

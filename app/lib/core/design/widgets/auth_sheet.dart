import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_colors.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// The rounded-top surface that overlaps the hero and holds the form; it scrolls when the screen is short
/// (keyboard open) and pins [footer] to its bottom otherwise.
/// PT: A superfície de topo arredondado que sobrepõe o hero e guarda o formulário; rola quando a tela é baixa
/// (teclado aberto) e fixa o [footer] no fim caso contrário.
/// Notes: docs/code-notes/app-core.md#authsheet
class AuthSheet extends StatelessWidget {
  const AuthSheet({required this.child, super.key, this.footer});

  final Widget child;
  final Widget? footer;

  static const radius = 32.0;
  static const _maxFormWidth = 420.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 6,
      shadowColor: BrandGradients.of(context).glowColor,
      // A faint light edge on the rounded top, like the glass panels of the signed-in screens.
      // PT: Uma borda de luz tênue no topo arredondado, como os painéis de vidro das telas logadas.
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(radius)),
        side: BorderSide(color: Colors.white.withValues(alpha: AppGlass.borderHighlightAlpha / 2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        // No intrinsic sizes: the column is at least as tall as the sheet and `spaceBetween` pushes the
        // footer down; a taller form just scrolls.
        // PT: Sem tamanhos intrínsecos: a coluna tem pelo menos a altura da folha e o `spaceBetween` empurra o
        // rodapé para baixo; um formulário mais alto apenas rola.
        builder: (context, viewport) => SingleChildScrollView(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: viewport.maxHeight,
                maxWidth: _maxFormWidth + 2 * AppSpacing.l,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.l,
                  AppSpacing.l + AppSpacing.xs,
                  AppSpacing.l,
                  AppSpacing.s + MediaQuery.paddingOf(context).bottom,
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
    );
  }
}

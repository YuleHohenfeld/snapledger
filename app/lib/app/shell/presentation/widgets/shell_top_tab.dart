import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_colors.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// One primary destination of the top bar: a text button, highlighted when [selected]; focusable, with
/// hover and a click cursor from the button itself.
/// PT: Um destino principal da barra superior: um botão de texto, destacado quando [selected]; focável, com
/// hover e cursor de clique vindos do próprio botão.
/// Notes: docs/code-notes/app-core.md#responsive-shell
class ShellTopTab extends StatelessWidget {
  const ShellTopTab({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  static const _horizontalPadding = AppSpacing.m;
  static const _underlineWidth = 28.0;
  static const _underlineHeight = 3.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final gradients = BrandGradients.of(context);
    // Merges with the button's own semantics (label, tap, focus) and adds the selected state.
    // PT: Junta-se à semântica do próprio botão (rótulo, toque, foco) e acrescenta o estado selecionado.
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(
                foregroundColor: selected ? colors.onSurface : colors.onSurfaceVariant,
                backgroundColor: selected
                    ? colors.primaryContainer.withValues(alpha: AppGlass.topTabSelectedAlpha)
                    : null,
                padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
                shape: const StadiumBorder(),
                textStyle: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: selected ? FontWeight.w700 : null),
              ),
              child: Text(label),
            ),
            // The glowing underline of the selected tab; an empty slot keeps the height of the others.
            // PT: O sublinhado brilhante da aba selecionada; um espaço vazio mantém a altura das outras.
            ExcludeSemantics(
              child: selected
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: gradients.accentGradient,
                        borderRadius: BorderRadius.circular(_underlineHeight),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.cyan.withValues(alpha: AppGlass.glowAlpha),
                            blurRadius: AppGlass.glowBlur / 2,
                          ),
                        ],
                      ),
                      child: const SizedBox(width: _underlineWidth, height: _underlineHeight),
                    )
                  : const SizedBox(height: _underlineHeight),
            ),
          ],
        ),
      ),
    );
  }
}

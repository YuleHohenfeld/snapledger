import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// The primary pill button with the brand gradient. While [busy] it is disabled and shows a spinner, so it
/// cannot be tapped twice; a null [onPressed] disables it too.
/// PT: O botão principal em pílula com o gradiente da marca. Enquanto [busy] fica desativado e mostra um
/// spinner, para não ser tocado duas vezes; [onPressed] nulo também o desativa.
/// Notes: docs/code-notes/app-auth.md#design-widgets
class GradientButton extends StatelessWidget {
  const GradientButton({required this.label, required this.onPressed, super.key, this.busy = false});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  static const _spinnerSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final gradients = BrandGradients.of(context);
    final enabled = !busy && onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : (busy ? 0.85 : 0.5),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          gradient: gradients.buttonGradient,
          shape: const StadiumBorder(),
          shadows: enabled
              ? [
                  BoxShadow(
                    color: gradients.glowColor.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: FilledButton(
          // Transparent: the gradient behind it is the fill; white text passes AA on every stop.
          // PT: Transparente: o gradiente atrás é o preenchimento; texto branco passa no AA em todo ponto.
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: gradients.onHero,
            disabledForegroundColor: gradients.onHero,
            shadowColor: Colors.transparent,
          ),
          onPressed: enabled ? onPressed : null,
          child: busy
              ? Semantics(
                  label: label,
                  child: SizedBox.square(
                    dimension: _spinnerSize,
                    child: CircularProgressIndicator(strokeWidth: 2, color: gradients.onHero),
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// A circle holding an [icon], with a soft radial glow around it; decoration only (no semantics).
/// PT: Um círculo com um [icon], com um brilho radial suave ao redor; só decoração (sem semântica).
/// Notes: docs/code-notes/app-core.md#brandgradients
class GlowOrb extends StatelessWidget {
  const GlowOrb({required this.icon, required this.color, super.key, this.size = 88});

  final IconData icon;

  /// The accent: the glow, the border and the icon (brand blue, or the success green).
  /// PT: O destaque: o brilho, a borda e o ícone (azul da marca, ou o verde de sucesso).
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final halo = size * 0.5;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -halo,
              top: -halo,
              right: -halo,
              bottom: -halo,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Icon(icon, size: size * 0.45, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

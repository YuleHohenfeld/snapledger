import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// A thin rectangle outline with a small dot on each corner, around [child]: the "scanner" look.
/// PT: Um contorno fino de retângulo com um pontinho em cada canto, ao redor de [child]: o visual de "scanner".
/// Notes: docs/code-notes/app-core.md#scanframe
class ScanFrame extends StatelessWidget {
  const ScanFrame({
    required this.child,
    super.key,
    this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
  });

  final Widget child;

  /// Defaults to [BrandGradients.frameColor].
  /// PT: O padrão é [BrandGradients.frameColor].
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _FramePainter(color ?? BrandGradients.of(context).frameColor),
    child: Padding(padding: padding, child: child),
  );
}

class _FramePainter extends CustomPainter {
  const _FramePainter(this.color);

  final Color color;

  static const _stroke = 1.0;
  static const _dot = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect.deflate(_stroke / 2),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );
    final fill = Paint()..color = color;
    for (final corner in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      canvas.drawCircle(corner, _dot, fill);
    }
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => oldDelegate.color != color;
}

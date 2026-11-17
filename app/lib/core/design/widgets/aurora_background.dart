import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// The hero background: the brand gradient with a few soft glowing orbs drifting slowly. Static when the
/// system asks to reduce motion (the controller never runs).
/// PT: O fundo do hero: o gradiente da marca com alguns orbes brilhantes e suaves à deriva. Estático quando o
/// sistema pede menos movimento (o controller nem roda).
/// Notes: docs/code-notes/app-core.md#aurorabackground
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, this.child});

  final Widget? child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  static const _period = Duration(seconds: 18);
  static const _restingPhase = 0.25;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _period,
    value: _restingPhase,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradients = BrandGradients.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradients.heroGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Decoration only: nothing here is read by a screen reader.
          // PT: Só decoração: nada aqui é lido por leitor de tela.
          ExcludeSemantics(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _OrbsPainter(phase: _controller, glow: gradients.glowColor),
              ),
            ),
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

class _OrbsPainter extends CustomPainter {
  _OrbsPainter({required this.phase, required this.glow}) : super(repaint: phase);

  final Animation<double> phase;
  final Color glow;

  // Center (fraction of the box), radius (fraction of the width), drift direction and glow strength.
  // PT: Centro (fração da caixa), raio (fração da largura), direção da deriva e força do brilho.
  static const _orbs = [
    (x: 0.85, y: 0.15, r: 0.55, dir: 1.0, alpha: 0.55),
    (x: 0.1, y: 0.7, r: 0.45, dir: -1.0, alpha: 0.4),
    (x: 0.55, y: 1.0, r: 0.6, dir: 0.6, alpha: 0.3),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase.value * 2 * math.pi;
    for (final orb in _orbs) {
      final dx = math.sin(t * orb.dir) * size.width * 0.06;
      final dy = math.cos(t * orb.dir) * size.height * 0.08;
      final pulse = 1 + 0.08 * math.sin(t + orb.x * 5);
      final center = Offset(size.width * orb.x + dx, size.height * orb.y + dy);
      final radius = size.width * orb.r * pulse;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [glow.withValues(alpha: orb.alpha), glow.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbsPainter oldDelegate) => oldDelegate.glow != glow;
}

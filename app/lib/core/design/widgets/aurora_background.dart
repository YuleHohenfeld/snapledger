import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_colors.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// A moving aurora: soft glowing orbs drifting slowly over a gradient. The default is the auth hero (brand
/// gradient, blue orbs); [AuroraBackground.ambient] is the signed-in backdrop (ink navy, faint blue / violet /
/// cyan orbs and a very faint grid). Static when the system asks to reduce motion (the controller never runs).
/// PT: Uma aurora em movimento: orbes brilhantes e suaves à deriva sobre um gradiente. O padrão é o hero de auth
/// (gradiente da marca, orbes azuis); [AuroraBackground.ambient] é o fundo da área logada (azul-marinho, orbes
/// tênues azul / violeta / ciano e uma grade bem fraca). Estática quando o sistema pede menos movimento (o
/// controller nem roda).
/// Notes: docs/code-notes/app-core.md#aurorabackground
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, this.child, this.animated = true}) : ambient = false;

  const AuroraBackground.ambient({super.key, this.child, this.animated = true}) : ambient = true;

  final Widget? child;

  /// The quiet signed-in variant (low alpha, slower, with a grid) instead of the hero.
  /// PT: A variante discreta da área logada (alfa baixo, mais lenta, com grade) em vez do hero.
  final bool ambient;

  /// False paints the static resting phase and never starts the controller (a page pushed above another
  /// aurora, so two of them do not tick).
  /// PT: Falso pinta a fase de repouso estática e nunca inicia o controller (uma página empilhada sobre outra
  /// aurora, para duas delas não rodarem).
  /// Notes: docs/code-notes/app-core.md#aurorabackground
  final bool animated;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  static const _heroPeriod = Duration(seconds: 18);
  static const _ambientPeriod = Duration(seconds: 40);
  static const _restingPhase = 0.25;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.ambient ? _ambientPeriod : _heroPeriod,
    value: _restingPhase,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(AuroraBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animated != widget.animated) _syncMotion();
  }

  void _syncMotion() {
    if (!widget.animated || MediaQuery.disableAnimationsOf(context)) {
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
    final ambient = widget.ambient;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: ambient
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.background, AppColors.surface],
              )
            : gradients.heroGradient,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Decoration only: nothing here is read by a screen reader. Each layer has its own repaint
          // boundary, so the drifting orbs never repaint the page and the grid is painted once.
          // PT: Só decoração: nada aqui é lido por leitor de tela. Cada camada tem a própria repaint boundary,
          // então os orbes à deriva nunca repintam a página e a grade é pintada uma vez.
          ExcludeSemantics(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _OrbsPainter(
                  phase: _controller,
                  orbs: ambient ? _ambientOrbs : _heroOrbs(gradients.glowColor),
                ),
              ),
            ),
          ),
          if (ambient)
            const ExcludeSemantics(
              child: RepaintBoundary(child: CustomPaint(painter: _GridPainter())),
            ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }

  // Hero orbs: all in the theme's glow color.
  // PT: Orbes do hero: todos na cor de brilho do tema.
  static List<_Orb> _heroOrbs(Color glow) => [
    _Orb(x: 0.85, y: 0.15, r: 0.55, dir: 1, alpha: 0.55, color: glow),
    _Orb(x: 0.1, y: 0.7, r: 0.45, dir: -1, alpha: 0.4, color: glow),
    _Orb(x: 0.55, y: 1, r: 0.6, dir: 0.6, alpha: 0.3, color: glow),
  ];

  // Ambient orbs: the three brand accents, quiet enough to keep any text readable over them.
  // PT: Orbes ambiente: os três acentos da marca, discretos o bastante para qualquer texto continuar legível.
  static const _ambientOrbs = [
    _Orb(x: 0.9, y: 0.1, r: 0.6, dir: 1, alpha: AppGlass.orbAlpha, color: AppColors.brand),
    _Orb(
      x: 0.05,
      y: 0.75,
      r: 0.5,
      dir: -1,
      alpha: AppGlass.orbVioletAlpha,
      color: AppColors.violet,
    ),
    _Orb(x: 0.6, y: 1, r: 0.55, dir: 0.6, alpha: AppGlass.orbCyanAlpha, color: AppColors.cyan),
  ];
}

/// One orb: center (fraction of the box), radius (fraction of the width), drift direction, glow strength, color.
/// PT: Um orbe: centro (fração da caixa), raio (fração da largura), direção da deriva, força do brilho, cor.
@immutable
class _Orb {
  const _Orb({
    required this.x,
    required this.y,
    required this.r,
    required this.dir,
    required this.alpha,
    required this.color,
  });

  final double x;
  final double y;
  final double r;
  final double dir;
  final double alpha;
  final Color color;

  // Value equality, so the painter can tell a rebuild with the same orbs from a real change.
  // PT: Igualdade por valor, para o painter distinguir um rebuild com os mesmos orbes de uma mudança real.
  @override
  bool operator ==(Object other) =>
      other is _Orb &&
      other.x == x &&
      other.y == y &&
      other.r == r &&
      other.dir == dir &&
      other.alpha == alpha &&
      other.color == color;

  @override
  int get hashCode => Object.hash(x, y, r, dir, alpha, color);
}

class _OrbsPainter extends CustomPainter {
  _OrbsPainter({required this.phase, required this.orbs}) : super(repaint: phase);

  final Animation<double> phase;
  final List<_Orb> orbs;

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase.value * 2 * math.pi;
    for (final orb in orbs) {
      final dx = math.sin(t * orb.dir) * size.width * 0.06;
      final dy = math.cos(t * orb.dir) * size.height * 0.08;
      final pulse = 1 + 0.08 * math.sin(t + orb.x * 5);
      final center = Offset(size.width * orb.x + dx, size.height * orb.y + dy);
      final radius = size.width * orb.r * pulse;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            orb.color.withValues(alpha: orb.alpha),
            orb.color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbsPainter oldDelegate) => !listEquals(oldDelegate.orbs, orbs);
}

/// A very faint square grid, painted once (it never changes, so it is never repainted).
/// PT: Uma grade quadrada bem fraca, pintada uma vez (nunca muda, então nunca é repintada).
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: AppGlass.gridAlpha)
      ..strokeWidth = AppGlass.gridLineWidth;
    for (var x = 0.0; x <= size.width; x += AppGlass.gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += AppGlass.gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

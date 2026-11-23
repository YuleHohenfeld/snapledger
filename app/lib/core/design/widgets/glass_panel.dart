import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_colors.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// A translucent "glass" panel: the container color at partial alpha (the aurora shows through a little), a 1px
/// gradient border (white highlight fading out) and a soft shadow. No `BackdropFilter`: a blur per row would be
/// costly on the web, and the translucent fill already reads as glass over the quiet aurora. Ink effects of
/// the [child] (taps on a `ListTile`) paint above the fill.
/// PT: Um painel de "vidro" translúcido: a cor do container com alfa parcial (a aurora aparece um pouco), borda
/// de 1px em gradiente (realce branco que some) e sombra suave. Sem `BackdropFilter`: um desfoque por linha seria
/// caro na web, e o preenchimento translúcido já parece vidro sobre a aurora discreta. Os efeitos de toque do
/// [child] (toques num `ListTile`) pintam acima do preenchimento.
/// Notes: docs/code-notes/app-core.md#glass-surfaces
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    super.key,
    this.padding = EdgeInsets.zero,
    this.radius = AppGlass.panelRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return CustomPaint(
      foregroundPainter: _GlassBorderPainter(radius: radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.container.withValues(alpha: AppGlass.panelAlpha),
          borderRadius: shape,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: AppGlass.panelShadowAlpha),
              blurRadius: AppGlass.panelShadowBlur,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: Material(
            type: MaterialType.transparency,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// The gradient hairline around a glass surface; it never changes, so it only repaints on a new radius.
/// PT: O fio de gradiente ao redor de uma superfície de vidro; nunca muda, então só repinta com outro raio.
class _GlassBorderPainter extends CustomPainter {
  const _GlassBorderPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppGlass.borderWidth
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: AppGlass.borderHighlightAlpha),
          Colors.white.withValues(alpha: AppGlass.borderFadeAlpha),
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)).deflate(AppGlass.borderWidth / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GlassBorderPainter oldDelegate) => oldDelegate.radius != radius;
}

/// Which edge of a [GlassBar] carries the glowing gradient line (the one facing the content).
/// PT: Qual borda de uma [GlassBar] leva a linha de gradiente brilhante (a que fica de frente para o conteúdo).
enum GlassEdge { top, bottom, end }

/// A navigation bar surface (top bar, bottom bar, rail): translucent dark glass with a thin blue-cyan-violet line
/// on one edge. Nothing scrolls behind these bars (the body sits beside them), so no blur is used: it would only
/// re-blur the moving aurora on every frame.
/// PT: Uma superfície de barra de navegação (superior, inferior, rail): vidro escuro translúcido com uma linha fina
/// azul-ciano-violeta numa borda. Nada rola atrás dessas barras (o corpo fica ao lado), então não há desfoque:
/// ele só re-desfocaria a aurora em movimento a cada frame.
/// Notes: docs/code-notes/app-core.md#glass-surfaces
class GlassBar extends StatelessWidget {
  const GlassBar({required this.edge, required this.child, super.key});

  final GlassEdge edge;
  final Widget child;

  static const _lineThickness = 1.0;

  @override
  Widget build(BuildContext context) {
    final gradients = BrandGradients.of(context);
    final vertical = edge == GlassEdge.end;
    final line = ExcludeSemantics(
      child: Opacity(
        opacity: AppGlass.barLineAlpha,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: gradients.accentGradient),
          child: SizedBox(
            width: vertical ? _lineThickness : null,
            height: vertical ? null : _lineThickness,
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.surface.withValues(alpha: AppGlass.barAlpha)),
      child: Stack(
        children: [
          child,
          switch (edge) {
            GlassEdge.top => Positioned(top: 0, left: 0, right: 0, child: line),
            GlassEdge.bottom => Positioned(bottom: 0, left: 0, right: 0, child: line),
            GlassEdge.end => PositionedDirectional(end: 0, top: 0, bottom: 0, child: line),
          },
        ],
      ),
    );
  }
}

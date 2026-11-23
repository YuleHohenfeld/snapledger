import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_colors.dart';
import 'package:snapledger/core/design/app_theme.dart';

/// A hero card in tinted glass (brand blue fading into violet over the dark surface) with a soft glow; only
/// light text ([BrandGradients.onHero]) goes on it.
/// PT: Um card hero em vidro tingido (azul da marca esmaecendo em violeta sobre a superfície escura) com um brilho
/// suave; só texto claro ([BrandGradients.onHero]) vai nele.
/// Notes: docs/code-notes/app-core.md#glass-surfaces
class GradientCard extends StatelessWidget {
  const GradientCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gradients = BrandGradients.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        // A translucent tint over the dark navy: white text stays above 7:1 even on the lightest point.
        // PT: Uma tinta translúcida sobre o azul-marinho: o texto branco fica acima de 7:1 até no ponto mais claro.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.brand.withValues(alpha: AppGlass.totalCardBrandAlpha),
            AppColors.violet.withValues(alpha: AppGlass.totalCardVioletAlpha),
          ],
        ),
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppGlass.panelRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: AppGlass.borderHighlightAlpha),
          width: AppGlass.borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: gradients.glowColor.withValues(alpha: AppGlass.glowAlpha),
            blurRadius: AppGlass.glowBlur,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

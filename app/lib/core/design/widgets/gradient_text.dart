import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_colors.dart';

/// Text filled with the bright blue-cyan-violet gradient (the brand mark). The stops are the light tints, so
/// every part of the text keeps at least 3:1 on the dark surfaces (it is used only for large, bold text).
/// PT: Texto preenchido com o gradiente brilhante azul-ciano-violeta (a marca). Os pontos são os tons claros, então
/// cada parte do texto mantém pelo menos 3:1 nas superfícies escuras (só é usado em texto grande e em negrito).
/// Notes: docs/code-notes/app-core.md#dark-ai-theme
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  static const gradient = LinearGradient(
    colors: [AppColors.primary, AppColors.cyan, AppColors.violet],
  );

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (bounds) => gradient.createShader(bounds),
    child: Text(
      text,
      style: style?.copyWith(color: AppColors.onBrand) ?? const TextStyle(color: AppColors.onBrand),
    ),
  );
}

import 'package:flutter/material.dart';

/// The dark "AI" palette: deep navy ink surfaces, the brand blue with a brighter tint for text and icons,
/// and cyan / violet accents. Hand-tuned (not seeded) so every pair keeps its WCAG AA ratio.
/// PT: A paleta escura "AI": superfícies azul-marinho profundo, o azul da marca com um tom mais claro para texto
/// e ícones, e acentos ciano / violeta. Ajustada à mão (sem semente) para cada par manter o contraste WCAG AA.
/// Notes: docs/code-notes/app-core.md#dark-ai-theme
abstract final class AppColors {
  // Surfaces, from the page background up to the highest container.
  // PT: Superfícies, do fundo da página até o container mais alto.
  static const background = Color(0xFF070B1A);
  static const surface = Color(0xFF0E1430);
  static const containerLowest = Color(0xFF0A0F25);
  static const containerLow = Color(0xFF121936);
  static const container = Color(0xFF161E40);
  static const containerHigh = Color(0xFF1C2650);
  static const containerHighest = Color(0xFF232E60);

  // Text and lines.
  // PT: Texto e linhas.
  static const onSurface = Color(0xFFE8ECFA);
  static const onSurfaceVariant = Color(0xFFA9B4D6);
  static const outline = Color(0xFF7280B0);
  static const outlineVariant = Color(0xFF2A3562);

  // Brand blue: [brand] fills gradients and buttons; [primary] is its bright tint for text and icons on dark.
  // PT: Azul da marca: [brand] preenche gradientes e botões; [primary] é o tom claro dele para texto e ícones no escuro.
  static const brand = Color(0xFF2F5BEA);
  static const primary = Color(0xFF86A8FF);
  static const onPrimary = Color(0xFF06143D);
  static const primaryContainer = Color(0xFF1E3FA6);
  static const onPrimaryContainer = Color(0xFFDCE6FF);

  // Accents: cyan and violet, the other two stops of the brand gradient.
  // PT: Acentos: ciano e violeta, os outros dois pontos do gradiente da marca.
  static const cyan = Color(0xFF4FD8EB);
  static const onCyan = Color(0xFF00323A);
  static const cyanContainer = Color(0xFF0B4A55);
  static const onCyanContainer = Color(0xFFC2F4FB);
  static const violet = Color(0xFFB59BFF);
  static const onViolet = Color(0xFF22095E);
  static const violetContainer = Color(0xFF3F2A8A);
  static const onVioletContainer = Color(0xFFE5DCFF);

  // Errors on dark: a soft red that stays readable on the navy surfaces.
  // PT: Erros no escuro: um vermelho suave que continua legível nas superfícies azul-marinho.
  static const error = Color(0xFFFF8F9E);
  static const onError = Color(0xFF42061A);
  static const errorContainer = Color(0xFF5E1428);
  static const onErrorContainer = Color(0xFFFFD9DF);

  /// Text and icons on the brand gradient (the buttons, the hero).
  /// PT: Texto e ícones sobre o gradiente da marca (os botões, o hero).
  static const onBrand = Color(0xFFFFFFFF);
}

/// Opacities, radii and shadows of the translucent "glass" surfaces (no blur) and of the living background.
/// PT: Opacidades, raios e sombras das superfícies translúcidas de "vidro" (sem desfoque) e do fundo vivo.
/// Notes: docs/code-notes/app-core.md#glass-surfaces
abstract final class AppGlass {
  /// Fill of a panel: the container color at this alpha, so the aurora shows through a little.
  /// PT: Preenchimento de um painel: a cor do container com este alfa, para a aurora aparecer um pouco.
  static const panelAlpha = 0.68;

  /// Fill of the top bar / navigation bars (translucent only, no blur).
  /// PT: Preenchimento da barra superior / de navegação (só translúcido, sem desfoque).
  static const barAlpha = 0.72;

  /// The 1px border: a white highlight on the top-left fading out toward the bottom-right.
  /// PT: A borda de 1px: um realce branco no canto superior esquerdo que some rumo ao inferior direito.
  static const borderHighlightAlpha = 0.20;
  static const borderFadeAlpha = 0.05;
  static const borderWidth = 1.0;

  static const panelRadius = 20.0;
  static const rowRadius = 16.0;
  static const markRadius = 10.0;

  /// Soft glow under a panel, and the stronger one of the hero total card.
  /// PT: Brilho suave sob um painel, e o mais forte do card de total.
  static const panelShadowAlpha = 0.35;
  static const panelShadowBlur = 24.0;
  static const glowAlpha = 0.35;
  static const glowBlur = 18.0;

  /// The glowing gradient line on the edge of a bar, and the fill of the selected top tab.
  /// PT: A linha de gradiente brilhante na borda de uma barra, e o preenchimento da aba superior selecionada.
  static const barLineAlpha = 0.55;
  static const topTabSelectedAlpha = 0.5;

  /// The brand-blue indicator behind the selected bottom bar / rail destination.
  /// PT: O indicador azul da marca atrás do destino selecionado da barra inferior / rail.
  static const navIndicatorAlpha = 0.45;

  /// The tint stops of the hero total card (brand blue fading into violet).
  /// PT: Os pontos da tinta do card de total (azul da marca esmaecendo em violeta).
  static const totalCardBrandAlpha = 0.6;
  static const totalCardVioletAlpha = 0.32;

  // The living background: the brand orb, then the violet and cyan ones at a fraction of it.
  // PT: O fundo vivo: o orbe da marca, depois o violeta e o ciano numa fração dele.
  static const orbAlpha = 0.22;
  static const orbVioletAlpha = 0.176;
  static const orbCyanAlpha = 0.132;
  static const gridAlpha = 0.035;
  static const gridSpacing = 56.0;
  static const gridLineWidth = 1.0;
}

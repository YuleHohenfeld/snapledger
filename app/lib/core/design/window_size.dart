import 'package:flutter/widgets.dart';

/// Width breakpoints (dp) of the Material 3 window size classes, and the content widths used with them.
/// PT: Pontos de quebra de largura (dp) das classes de tamanho de janela do Material 3, e as larguras de conteúdo.
/// Notes: docs/code-notes/app-core.md#responsive-shell
abstract final class AppBreakpoints {
  /// From here up: medium (a navigation rail).
  /// PT: Daqui para cima: medium (uma navigation rail).
  static const double medium = 600;

  /// From here up: expanded (the top bar).
  /// PT: Daqui para cima: expanded (a barra superior).
  static const double expanded = 840;

  /// Max width of lists, forms, profile and categories on a wide window.
  /// PT: Largura máxima de listas, formulários, perfil e categorias numa janela larga.
  static const double contentWidth = 760;

  /// Max width of the summary, which has two columns on an expanded window.
  /// PT: Largura máxima do resumo, que tem duas colunas numa janela expandida.
  static const double dashboardWidth = 1100;
}

/// The Material 3 window size class of the current width; decided by width, never by platform.
/// PT: A classe de tamanho de janela do Material 3 para a largura atual; decidida pela largura, nunca pela plataforma.
/// Notes: docs/code-notes/app-core.md#responsive-shell
enum WindowSize {
  compact,
  medium,
  expanded;

  static WindowSize ofWidth(double width) {
    if (width >= AppBreakpoints.expanded) return expanded;
    if (width >= AppBreakpoints.medium) return medium;
    return compact;
  }

  static WindowSize of(BuildContext context) => ofWidth(MediaQuery.sizeOf(context).width);

  /// True when the app shell shows the top bar (so pages drop their own title bar and add button).
  /// PT: Verdadeiro quando a moldura do app mostra a barra superior (as páginas tiram a própria barra e o botão de adicionar).
  bool get hasTopBar => this == expanded;
}

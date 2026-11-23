import 'package:flutter/material.dart';
import 'package:snapledger/core/design/widgets/aurora_background.dart';

/// The living background of a signed-in screen: the ambient aurora fills the area and the `Scaffold`s below
/// are made transparent, so they show it. The aurora has an opaque base, so a pushed page that wraps itself
/// in its own backdrop never lets the page under it show through during a route transition.
/// PT: O fundo vivo de uma tela logada: a aurora ambiente preenche a área e os `Scaffold`s abaixo ficam
/// transparentes, então a mostram. A aurora tem base opaca, então uma página empilhada que se envolve no próprio
/// fundo nunca deixa a página de baixo aparecer durante a transição de rota.
/// Notes: docs/code-notes/app-core.md#living-background
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({required this.child, this.animated = true, super.key});

  final Widget child;

  /// False for a page pushed above the shell, whose own backdrop is already moving: this one stays still.
  /// PT: Falso para uma página empilhada sobre a moldura, cujo fundo já se move: este fica parado.
  final bool animated;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(scaffoldBackgroundColor: Colors.transparent),
    child: AuroraBackground.ambient(animated: animated, child: child),
  );
}

import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/aurora_background.dart';
import 'package:snapledger/core/design/widgets/auth_sheet.dart';
import 'package:snapledger/core/design/widgets/brand_header.dart';

/// How tall the gradient hero is: [tall] (login, ~38% of the screen) or [compact] (~24%).
/// PT: A altura do hero em gradiente: [tall] (login, ~38% da tela) ou [compact] (~24%).
enum AuthHeroSize {
  tall(0.38),
  compact(0.24);

  const AuthHeroSize(this.fraction);

  final double fraction;
}

/// An auth page: a gradient hero (brand, optional white back arrow) and a rounded [AuthSheet] over it with
/// the form and an optional pinned [footer]. With the keyboard open the hero shrinks to a thin bar.
/// PT: Uma página de auth: um hero em gradiente (marca, seta de voltar branca opcional) e uma [AuthSheet]
/// arredondada sobre ele com o formulário e um [footer] fixo opcional. Com o teclado aberto o hero vira uma faixa.
/// Notes: docs/code-notes/app-auth.md#design-widgets
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.child,
    super.key,
    this.footer,
    this.onBack,
    this.heroSize = AuthHeroSize.compact,
  });

  final Widget child;
  final Widget? footer;
  final AuthHeroSize heroSize;

  /// When set, a white back arrow (no title) appears in the hero; secondary screens use it.
  /// PT: Quando definido, uma seta de voltar branca (sem título) aparece no hero; as telas secundárias a usam.
  final VoidCallback? onBack;

  static const _barHeight = 56.0;
  static const _minTallVisible = 188.0;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final top = MediaQuery.paddingOf(context).top;
    final compact = keyboardOpen || heroSize == AuthHeroSize.compact;
    const overlap = AuthSheet.radius;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          final minHeight = top + _barHeight + overlap;
          final wanted = box.maxHeight * heroSize.fraction;
          final tallMin = top + _minTallVisible + overlap;
          final heroHeight = keyboardOpen
              ? minHeight
              : wanted.clamp(heroSize == AuthHeroSize.tall ? tallMin : minHeight, double.infinity);
          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: heroHeight,
                child: AuroraBackground(
                  child: Padding(
                    padding: EdgeInsets.only(top: top, bottom: overlap),
                    child: compact
                        ? _CompactHero(onBack: onBack)
                        : const Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: EdgeInsets.only(top: 24),
                              child: BrandHeader(),
                            ),
                          ),
                  ),
                ),
              ),
              Positioned(
                top: heroHeight - overlap,
                left: 0,
                right: 0,
                bottom: 0,
                child: AuthSheet(footer: footer, child: child),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CompactHero extends StatelessWidget {
  const _CompactHero({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: AuthScaffold._barHeight,
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (onBack != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: BackButton(onPressed: onBack, color: BrandGradients.of(context).onHero),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 56),
          child: BrandHeader(compact: true),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The brand block of the auth screens: icon in a tinted circle, app name and tagline.
/// PT: O bloco de marca das telas de autenticação: ícone num círculo colorido, nome do app e slogan.
/// Notes: docs/code-notes/app-auth.md#design-widgets
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  static const _circleSize = 72.0;
  static const _iconSize = 36.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        // The icon is decoration: the name below already says who we are.
        // PT: O ícone é decoração: o nome abaixo já diz quem somos.
        ExcludeSemantics(
          child: Container(
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_balance_wallet_outlined,
              size: _iconSize,
              color: colors.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Text(
          AppBrand.name,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          AppLocalizations.of(context).brandTagline,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

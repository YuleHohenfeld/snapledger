import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// One line of a [RequirementsChecklist]: its text and whether the user already satisfies it.
/// PT: Uma linha de um [RequirementsChecklist]: o texto e se o usuário já a satisfaz.
@immutable
class Requirement {
  const Requirement({required this.label, required this.met});

  final String label;
  final bool met;
}

/// A live list of rules (for example password rules) that turn green as they are satisfied.
/// PT: Uma lista ao vivo de regras (por exemplo da senha) que ficam verdes conforme são atendidas.
/// Notes: docs/code-notes/app-auth.md#requirementschecklist
class RequirementsChecklist extends StatelessWidget {
  const RequirementsChecklist({required this.requirements, super.key});

  final List<Requirement> requirements;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final success = SuccessColors.of(context).success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final requirement in requirements)
          Semantics(
            label:
                '${requirement.label}, ${requirement.met ? l10n.requirementMet : l10n.requirementNotMet}',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Icon(
                      requirement.met ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 20,
                      color: requirement.met ? success : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text(
                        requirement.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: requirement.met ? success : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

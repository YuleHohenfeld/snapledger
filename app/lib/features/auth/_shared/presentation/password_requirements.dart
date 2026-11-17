import 'package:flutter/material.dart';
import 'package:snapledger/core/design/widgets/requirements_checklist.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The live checklist under a new-password field; it redraws on every keystroke of [controller].
/// PT: A checklist ao vivo sob um campo de nova senha; é redesenhada a cada tecla de [controller].
/// Notes: docs/code-notes/app-auth.md#requirementschecklist
class PasswordRequirements extends StatelessWidget {
  const PasswordRequirements({required this.controller, super.key});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => RequirementsChecklist(
        requirements: [
          Requirement(
            label: l10n.passwordRequirementMinLength(passwordMinBytes),
            met: passwordHasMinLength(controller.text),
          ),
        ],
      ),
    );
  }
}

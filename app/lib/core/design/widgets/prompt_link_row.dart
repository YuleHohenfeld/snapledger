import 'package:flutter/material.dart';

/// "Question? [Action]": plain text followed by a text button; wraps on narrow screens or big fonts.
/// PT: "Pergunta? [Ação]": texto simples seguido de um botão de texto; quebra em telas estreitas ou fontes grandes.
/// Notes: docs/code-notes/app-auth.md#design-widgets
class PromptLinkRow extends StatelessWidget {
  const PromptLinkRow({
    required this.prompt,
    required this.actionLabel,
    required this.onPressed,
    super.key,
  });

  final String prompt;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        prompt,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      TextButton(onPressed: onPressed, child: Text(actionLabel)),
    ],
  );
}

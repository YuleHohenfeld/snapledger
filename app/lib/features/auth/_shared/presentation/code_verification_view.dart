import 'package:flutter/material.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/form_error_banner.dart';
import 'package:snapledger/core/design/widgets/glow_orb.dart';
import 'package:snapledger/core/design/widgets/otp_code_input.dart';
import 'package:snapledger/core/design/widgets/resend_code_button.dart';
import 'package:snapledger/features/auth/_shared/application/code_entry_status.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// The "Check your email" screen body shared by password reset and verify email: icon, text with the
/// address, the six code boxes and the resend line. It holds no logic; the screens feed it state.
/// PT: O corpo da tela "Confira seu email" compartilhado por troca de senha e verificar email: ícone, texto com o
/// endereço, as seis caixas do código e a linha de reenviar. Não tem lógica; as telas o alimentam com o estado.
/// Notes: docs/code-notes/app-auth.md#otpcodeinput
class CodeVerificationView extends StatelessWidget {
  const CodeVerificationView({
    required this.email,
    required this.status,
    required this.codeController,
    required this.codeFocus,
    required this.cooldownSeconds,
    required this.resending,
    required this.onCodeCompleted,
    required this.onResend,
    super.key,
    this.errorText,
    this.banner,
    this.onCodeChanged,
  });

  final String email;
  final CodeEntryStatus status;
  final TextEditingController codeController;
  final FocusNode codeFocus;
  final int cooldownSeconds;
  final bool resending;
  final ValueChanged<String> onCodeCompleted;
  final VoidCallback onResend;
  final ValueChanged<String>? onCodeChanged;

  /// "That code is not right" under the boxes (the server refused the code).
  /// PT: "Esse código não está certo" sob as caixas (o servidor recusou o código).
  final String? errorText;

  /// Any other failure (too many attempts, no network), above the boxes.
  /// PT: Qualquer outra falha (muitas tentativas, sem rede), acima das caixas.
  final String? banner;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final success = SuccessColors.of(context);
    final verified = status == CodeEntryStatus.success;
    final body = l10n.codeVerificationBody(email);
    final at = body.indexOf(email);
    final muted = theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Decoration: the title below says what to do.
        // PT: Decoração: o título abaixo diz o que fazer.
        Center(
          child: GlowOrb(
            icon: verified ? Icons.check : Icons.mark_email_read_outlined,
            color: verified ? success.success : colors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        Semantics(
          header: true,
          child: Text(
            l10n.codeVerificationTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        // The address is bold: found in the localized sentence, so any translation works.
        // PT: O endereço fica em negrito: achado na frase traduzida, então qualquer tradução funciona.
        Text.rich(
          at < 0
              ? TextSpan(text: body)
              : TextSpan(
                  children: [
                    TextSpan(text: body.substring(0, at)),
                    TextSpan(
                      text: email,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: body.substring(at + email.length)),
                  ],
                ),
          textAlign: TextAlign.center,
          style: muted,
        ),
        const SizedBox(height: AppSpacing.xl),
        if (banner != null) ...[
          FormErrorBanner(message: banner!),
          const SizedBox(height: AppSpacing.m),
        ],
        OtpCodeInput(
          controller: codeController,
          focusNode: codeFocus,
          status: OtpStatus.values.byName(status.name),
          errorText: errorText,
          autofocus: true,
          onChanged: onCodeChanged,
          onCompleted: onCodeCompleted,
        ),
        const SizedBox(height: AppSpacing.m),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l10n.codeResendPrompt, style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
            ResendCodeButton(
              remainingSeconds: cooldownSeconds,
              busy: resending || status == CodeEntryStatus.verifying || verified,
              onPressed: onResend,
            ),
          ],
        ),
      ],
    );
  }
}

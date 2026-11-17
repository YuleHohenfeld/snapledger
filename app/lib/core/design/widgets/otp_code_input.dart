import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// What the code boxes show; the screen's ViewModel decides it, the widget only draws it.
/// PT: O que as caixas do código mostram; o ViewModel da tela decide, o widget só desenha.
/// Notes: docs/code-notes/app-auth.md#otpcodeinput
enum OtpStatus { idle, verifying, error, success }

/// Six square boxes driven by one hidden [TextField]: paste, autofill, backspace and the numeric
/// keyboard all work because the real input is still a text field.
/// PT: Seis caixas quadradas guiadas por um [TextField] escondido: colar, autofill, backspace e o teclado
/// numérico funcionam porque a entrada real continua sendo um campo de texto.
/// Notes: docs/code-notes/app-auth.md#otpcodeinput
class OtpCodeInput extends StatefulWidget {
  const OtpCodeInput({
    required this.controller,
    required this.focusNode,
    required this.onCompleted,
    super.key,
    this.status = OtpStatus.idle,
    this.errorText,
    this.onChanged,
    this.autofocus = false,
  });

  /// Number of digits of every code in the contract.
  /// PT: Quantidade de dígitos de todo código do contrato.
  static const length = 6;

  /// Owned by the screen's Controller; the widget only clears it when [status] becomes `error`.
  /// PT: Pertence ao Controller da tela; o widget só o limpa quando [status] vira `error`.
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Called once, with the 6 digits, as soon as the last digit is typed or pasted.
  /// PT: Chamado uma vez, com os 6 dígitos, assim que o último dígito é digitado ou colado.
  final ValueChanged<String> onCompleted;
  final OtpStatus status;

  /// Shown (and announced) under the boxes while [status] is `error`.
  /// PT: Mostrado (e anunciado) sob as caixas enquanto [status] é `error`.
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  State<OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<OtpCodeInput> with SingleTickerProviderStateMixin {
  static const _maxBox = 56.0;
  static const _gap = AppSpacing.s;
  static const _shake = Duration(milliseconds: 400);
  static const _slotHeight = 28.0;

  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: _shake,
  );

  // While the server decides, or after it accepted the code, typing is ignored (the keyboard stays).
  // PT: Enquanto o servidor decide, ou depois que aceitou o código, a digitação é ignorada (o teclado fica).
  bool get _locked => widget.status == OtpStatus.verifying || widget.status == OtpStatus.success;

  @override
  void didUpdateWidget(OtpCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == OtpStatus.error && oldWidget.status != OtpStatus.error) {
      if (!MediaQuery.disableAnimationsOf(context)) _shakeController.forward(from: 0);
      // After the frame: clearing a controller during build would notify the field mid-build.
      // PT: Depois do frame: limpar um controller durante o build notificaria o campo no meio do build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.status == OtpStatus.error) widget.controller.clear();
      });
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    widget.onChanged?.call(value);
    if (value.length == OtpCodeInput.length) widget.onCompleted(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _shakeController,
          builder: (context, child) {
            final t = _shakeController.value;
            final dx = math.sin(t * math.pi * 6) * 10 * (1 - t);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Stack(
            children: [
              ExcludeSemantics(
                child: ListenableBuilder(
                  listenable: Listenable.merge([widget.controller, widget.focusNode]),
                  builder: (context, _) => _boxes(context),
                ),
              ),
              Positioned.fill(
                child: Semantics(
                  label: l10n.codeSemanticsLabel,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    autofocus: widget.autofocus,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    autocorrect: false,
                    enableSuggestions: false,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    showCursor: false,
                    cursorWidth: 0,
                    // Invisible: the boxes draw the digits; this field only receives the input.
                    // PT: Invisível: as caixas desenham os dígitos; este campo só recebe a entrada.
                    style: const TextStyle(color: Colors.transparent, fontSize: 1),
                    decoration: const InputDecoration.collapsed(hintText: null),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(OtpCodeInput.length),
                      TextInputFormatter.withFunction(
                        (oldValue, newValue) => _locked ? oldValue : newValue,
                      ),
                    ],
                    onChanged: _onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        SizedBox(
          height: _slotHeight,
          child: Center(child: _belowBoxes(context, l10n, theme)),
        ),
      ],
    );
  }

  Widget _boxes(BuildContext context) {
    final text = widget.controller.text;
    final active = widget.focusNode.hasFocus && text.length < OtpCodeInput.length ? text.length : -1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < OtpCodeInput.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxBox),
              child: AspectRatio(
                aspectRatio: 1,
                child: _OtpBox(
                  digit: i < text.length ? text[i] : '',
                  active: i == active,
                  status: widget.status,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _belowBoxes(BuildContext context, AppLocalizations l10n, ThemeData theme) {
    switch (widget.status) {
      case OtpStatus.verifying:
        return Semantics(
          label: l10n.codeVerifying,
          child: const SizedBox(height: 4, child: LinearProgressIndicator()),
        );
      case OtpStatus.error:
        final message = widget.errorText;
        if (message == null) return const SizedBox.shrink();
        return Semantics(
          liveRegion: true,
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      case OtpStatus.success:
        return Semantics(
          liveRegion: true,
          label: l10n.codeVerified,
          child: Icon(Icons.check_circle, color: SuccessColors.of(context).success, size: 24),
        );
      case OtpStatus.idle:
        return const SizedBox.shrink();
    }
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({required this.digit, required this.active, required this.status});

  final String digit;
  final bool active;
  final OtpStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final success = SuccessColors.of(context).success;
    final (Color borderColor, double borderWidth) = switch (status) {
      OtpStatus.error => (colors.error, 2.0),
      OtpStatus.success => (success, 2.0),
      _ when active => (colors.primary, 2.0),
      _ => (digit.isEmpty ? colors.outlineVariant : colors.outline, 1.0),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.s + AppSpacing.xs),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Center(
        child: Text(
          digit,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: status == OtpStatus.success ? success : colors.onSurface,
          ),
        ),
      ),
    );
  }
}

#!/usr/bin/env bash
# SnapLedger app rules that can be checked by grep (see "Automatic checks" in app/CLAUDE.md).
# Usage:  scripts/claude/mvvmc_rules.sh <file> [<file> ...]
# Output: one line per finding, "ERROR|WARNING <file>:<line> [RULE] message".
# Exit:   1 if at least one ERROR, 0 otherwise (warnings never fail).
# Portable: macOS bash 3.2, BSD grep/sed. No arrays, no \b, no jq.
# PT: Regras do app SnapLedger verificáveis por grep (ver "Automatic checks" em app/CLAUDE.md).
# PT: Saída e códigos de saída iguais aos do api_rules.sh. Portável: bash 3.2 do macOS, sem jq.

out=""

add() { # level file line rule message
  out="${out}$1 $2:$3 [$4] $5
"
}

# grep -nE <regex> <file>, ignoring comment lines; calls add() for each hit.
# PT: grep -nE <regex> <arquivo>, ignorando linhas de comentário; chama add() para cada ocorrência.
check() { # level file regex rule message [grep-flags]
  hits=$(grep -n $6 -E "$3" "$2" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(//|\*|/\*)')
  [ -z "$hits" ] && return
  for line in $(printf '%s\n' "$hits" | cut -d: -f1); do
    add "$1" "$2" "$line" "$4" "$5"
  done
}

for f in "$@"; do
  [ -f "$f" ] || continue
  case "$f" in *app/*.dart) ;; *) continue ;; esac
  # Generated code is not written by hand.
  # PT: Código gerado não é escrito à mão.
  case "$f" in *.g.dart|*.freezed.dart|*/lib/l10n/gen/*) continue ;; esac

  in_lib=0; case "$f" in *app/lib/*) in_lib=1 ;; esac

  # D6: package imports only, so a moved file never breaks its importers silently.
  # PT: Só imports de pacote, assim mover um arquivo nunca quebra quem o importa em silêncio.
  check ERROR "$f" "^(import|export)[[:space:]]+['\"]\.\.?/" D6-RELATIVE-IMPORT \
    "Use package:snapledger/... imports (always_use_package_imports)."

  [ "$in_lib" -eq 1 ] || continue

  # D3: no console output in the app; it reaches device logs and may carry tokens or personal data.
  # PT: Sem saída de console no app; ela chega aos logs do aparelho e pode levar tokens ou dados pessoais.
  check ERROR "$f" '(^|[^A-Za-z0-9_.])(print|debugPrint)[[:space:]]*\(' D3-PRINT \
    "No print/debugPrint in lib/. Never log tokens, passwords, Authorization headers or personal data."

  # D4: tokens and passwords live only in flutter_secure_storage.
  # PT: Tokens e senhas ficam só no flutter_secure_storage.
  if grep -qiE 'token|password|secret' "$f"; then
    check ERROR "$f" 'SharedPreferences|shared_preferences|localStorage|sessionStorage|package:hive' D4-INSECURE-TOKEN-STORAGE \
      "Tokens and passwords are stored only through flutter_secure_storage (core/session)."
  fi

  # D5: money is Decimal parsed from the contract's decimal string, never a binary float.
  # PT: Dinheiro é Decimal lido da string decimal do contrato, nunca um float binário.
  check ERROR "$f" '(double|num)\??[[:space:]]+(get[[:space:]]+)?_?[A-Za-z]*(amount|total|price|balance|percentage)([[:space:]]*[;,=)}]|[[:space:]]*=>|[[:space:]]*$)' D5-FLOATING-MONEY \
    "Money and percentages are Decimal (from the contract's string), never double/num." -i

  # D7: the API address comes from --dart-define (core/config), never from a literal.
  # PT: O endereço da API vem do --dart-define (core/config), nunca de um literal.
  case "$f" in
    */lib/core/config/*) ;;
    *)
      check ERROR "$f" "['\"]https?://" D7-HARDCODED-URL \
        "No URL literals in lib/. API_BASE_URL is read once in lib/core/config/."
      ;;
  esac

  # D8: only the API client and repositories talk HTTP.
  # PT: Só o cliente da API e os repositórios falam HTTP.
  case "$f" in
    */lib/core/api/*|*/data/repositories/*) ;;
    *)
      check ERROR "$f" "^import[[:space:]]+['\"]package:(dio|http)/" D8-HTTP-OUTSIDE-DATA \
        "HTTP belongs to lib/core/api/ and */data/repositories/. Call a repository instead."
      ;;
  esac

  # D10: the Authorization header is set only by the AuthInterceptor.
  # PT: O header Authorization só é colocado pelo AuthInterceptor.
  case "$f" in
    */lib/core/api/*) ;;
    *)
      check ERROR "$f" "['\"]Authorization['\"]" D10-AUTH-HEADER-OUTSIDE-INTERCEPTOR \
        "Only the AuthInterceptor in lib/core/api/ attaches the Bearer token."
      ;;
  esac

  # D11: navigation state is owned by the router; no global navigator keys or static routers.
  # PT: O estado de navegação pertence ao router; sem chaves globais de navigator ou router estático.
  case "$f" in
    */lib/core/router/*) ;;
    *)
      check ERROR "$f" 'GlobalKey<NavigatorState>|static[[:space:]]+(final[[:space:]]+|late[[:space:]]+)*GoRouter' D11-GLOBAL-NAVIGATION \
        "Navigate with context.go/push or a navigation intent; the GoRouter lives in lib/core/router/."
      ;;
  esac

  case "$f" in
    */presentation/*)
      # D1: views never see data access.
      # PT: Views nunca enxergam acesso a dados.
      check ERROR "$f" "^import[[:space:]]+['\"][^'\"]*(/data/repositories/|/core/api/|package:(dio|http)/)" D1-DATA-IN-VIEW \
        "View -> Controller -> ViewModel -> Repository. A widget never imports a repository or the API client."
      # D9: user-facing text comes from AppLocalizations.
      # PT: Texto exibido ao usuário vem do AppLocalizations.
      check WARNING "$f" "Text\([[:space:]]*['\"]" D9-HARDCODED-UI-TEXT \
        "Use AppLocalizations.of(context) (lib/l10n/*.arb) for user-facing text."
      ;;
  esac

  case "$f" in
    */application/viewmodel/*|*_view_model.dart)
      # D2: ViewModels are plain Dart plus ChangeNotifier, testable without widgets.
      # PT: ViewModels são Dart puro mais ChangeNotifier, testáveis sem widgets.
      check ERROR "$f" "^import[[:space:]]+['\"]package:flutter/(material|widgets|cupertino|painting|rendering)\.dart|BuildContext|TextEditingController" D2-UI-IN-VIEWMODEL \
        "A ViewModel imports only package:flutter/foundation.dart from Flutter and never holds BuildContext or text controllers."
      ;;
  esac
done

out=$(printf '%s' "$out" | sed '/^$/d')
[ -n "$out" ] && printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^ERROR' && exit 1
exit 0

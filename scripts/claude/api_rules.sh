#!/usr/bin/env bash
# SnapLedger API rules that can be checked by grep (see "Automatic checks" in api/CLAUDE.md).
# Usage:  scripts/claude/api_rules.sh <file> [<file> ...]
# Output: one line per finding, "ERROR|WARNING <file>:<line> [RULE] message".
# Exit:   1 if at least one ERROR, 0 otherwise (warnings never fail).
# Portable: macOS bash 3.2, BSD grep/sed. No arrays, no \b, no jq.

out=""

add() { # level file line rule message
  out="${out}$1 $2:$3 [$4] $5
"
}

# grep -nE <regex> <file>, ignoring comment lines; calls add() for each hit.
check() { # level file regex rule message [grep-flags]
  hits=$(grep -n $6 -E "$3" "$2" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(//|\*|/\*|#)')
  [ -z "$hits" ] && return
  for line in $(printf '%s\n' "$hits" | cut -d: -f1); do
    add "$1" "$2" "$line" "$4" "$5"
  done
}

for f in "$@"; do
  [ -f "$f" ] || continue
  case "$f" in *api/*) ;; *) continue ;; esac

  is_test=0; case "$f" in *api/src/test/*) is_test=1 ;; esac

  case "$f" in
    *.java)
      if [ "$is_test" -eq 0 ]; then
        # A1: constructor injection only (tests may use @Autowired)
        check ERROR "$f" '@Autowired' A1-FIELD-INJECTION \
          "Use constructor injection (final fields + @RequiredArgsConstructor), not @Autowired."

        # A2 (Java): string literal assigned to something named like a secret
        check WARNING "$f" '(password|secret|api_?key|private_?key|token)[A-Za-z0-9_]*[[:space:]]*=[[:space:]]*"[^"]{6,}"' \
          A2-SECRET-LITERAL "Possible hard-coded secret. Secrets come only from environment variables." -i

        # A9: console output / swallowed stack traces
        check WARNING "$f" 'System\.(out|err)\.|printStackTrace\(' A9-SYSOUT \
          "Use the logger (and never log secrets or personal data)."
      fi

      # A3: CORS wildcard
      check ERROR "$f" '(allowedOrigins|AllowedOrigin|allowedOriginPatterns|AllowedOriginPattern|setAllowedOrigins)[A-Za-z]*\(.*"\*"' \
        A3-CORS-WILDCARD "CORS origins come from CORS_ALLOWED_ORIGINS. Never \"*\"."

      # A6: floating point for money
      check ERROR "$f" '(double|float)[[:space:]]+[A-Za-z_]*(amount|total|price|value|balance|percentage)' \
        A6-FLOATING-MONEY "Money and percentages use BigDecimal, never double/float." -i

      case "$f" in
        *Controller.java)
          # A4: no try/catch in controllers
          check ERROR "$f" '(^|[^A-Za-z0-9_])try[[:space:]]*[({]' A4-TRY-IN-CONTROLLER \
            "Controllers do not catch exceptions; throw ApiException and let GlobalExceptionHandler answer."
          # A5: controllers never see repositories
          check ERROR "$f" '^import .*Repository;' A5-REPO-IN-CONTROLLER \
            "Controller -> Service only. Move data access to the service."
          # A8: user id never comes from the request
          check ERROR "$f" '@(RequestParam|PathVariable|RequestBody|RequestHeader)[^;]*[[:space:]]userId|\{userId\}' \
            A8-USERID-FROM-REQUEST "The user id comes only from the token (@CurrentUserId)."
          ;;
      esac

      case "$f" in
        */dto/*Request.java)
          check ERROR "$f" '[[:space:](,]userId[[:space:],)]' A8-USERID-FROM-REQUEST \
            "Request records never carry userId; it comes from the token."
          ;;
      esac

      # A10: no @Data/@Setter/@EqualsAndHashCode on entities
      if grep -qE '^[[:space:]]*@Entity' "$f"; then
        check ERROR "$f" '^[[:space:]]*@(Data|Setter|EqualsAndHashCode)([[:space:](]|$)' A10-LOMBOK-DATA-ENTITY \
          "Entities use @Getter + protected no-args constructor and intention-revealing methods."
      fi
      ;;

    *.properties|*.yml|*.yaml)
      # A2: secret-like keys must use ${ENV}
      check ERROR "$f" '^[[:space:]]*[A-Za-z0-9_.-]*(password|secret|api-key|apikey|private-key|credentials?)[[:space:]]*[=:][[:space:]]*[^[:space:]$]' \
        A2-SECRET-LITERAL "Secret-like property with a literal value. Use \${ENV_VAR}." -i

      # A3: CORS wildcard in config
      check ERROR "$f" 'allowed-origins[[:space:]]*[=:][[:space:]]*.*\*' A3-CORS-WILDCARD \
        "CORS origins must be an explicit list. Never \"*\"."

      # A7: Flyway owns the schema
      check ERROR "$f" 'ddl-auto[[:space:]]*[=:][[:space:]]*[^v[:space:]]|ddl-auto[[:space:]]*[=:][[:space:]]*v[^a]|generate-ddl[[:space:]]*[=:][[:space:]]*true' \
        A7-DDL-AUTO "ddl-auto must be 'validate'. Change the schema with a Flyway migration." -i
      ;;
  esac
done

out=$(printf '%s' "$out" | sed '/^$/d')
[ -n "$out" ] && printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^ERROR' && exit 1
exit 0

#!/usr/bin/env bash
# Claude Code Stop hook: runs when Claude is about to finish a response.
# 1) project rules on every changed file (vs HEAD, plus untracked);
# 2) `./mvnw compile` when API sources changed (cached per content, Java 21 required);
# 2b) `flutter analyze` when app sources changed (cached per content, skipped without Flutter);
# 3) once per change set, asks for the security-reviewer when auth/security/secrets changed.
# Exit 2 => Claude does not stop and receives the reason on stderr.
# Portable: macOS bash 3.2, no jq.

input=$(cat)
# Avoid infinite loops: if Claude is already continuing because of this hook, let it stop.
printf '%s' "$input" | grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

changed=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
[ -z "$changed" ] && exit 0

existing=""
for f in $changed; do [ -f "$f" ] && existing="$existing $f"; done
[ -z "$existing" ] && exit 0

problems=""
cache="${TMPDIR:-/tmp}"

# --- 1) Rules -----------------------------------------------------------------
api_files=$(printf '%s\n' $existing | grep -E '^api/.*\.(java|properties|ya?ml)$')
if [ -n "$api_files" ]; then
  result=$(bash scripts/claude/api_rules.sh $api_files)
  if [ $? -ne 0 ]; then
    problems="$problems
## API rules (api/CLAUDE.md > Automatic checks)
$(printf '%s\n' "$result" | grep '^ERROR')"
  fi
fi

dart_files=$(printf '%s\n' $existing | grep -E '^app/.*\.dart$')
if [ -n "$dart_files" ] && [ -f scripts/claude/mvvmc_rules.sh ]; then
  result=$(bash scripts/claude/mvvmc_rules.sh $dart_files)
  if [ $? -ne 0 ]; then
    problems="$problems
## App rules (app/CLAUDE.md)
$(printf '%s\n' "$result" | grep '^ERROR')"
  fi
fi

# --- 2) API compiles ------------------------------------------------------------
compile_inputs=$(printf '%s\n' $existing | grep -E '^api/(src/main/.*\.java|pom\.xml)$')
if [ -n "$compile_inputs" ]; then
  signature=$(cat $compile_inputs | cksum | cut -d' ' -f1)
  marker="$cache/snapledger_compile_ok_$signature"
  java21=$(/usr/libexec/java_home -v 21 2>/dev/null)
  [ -z "$java21" ] && [ -d /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ] \
    && java21=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
  if [ ! -f "$marker" ] && [ -n "$java21" ]; then
    compile_out=$(cd api && JAVA_HOME="$java21" ./mvnw -q -B compile 2>&1)
    if [ $? -eq 0 ]; then
      touch "$marker"
    else
      problems="$problems
## ./mvnw compile failed
$(printf '%s\n' "$compile_out" | grep -E 'ERROR|error:' | head -20)"
    fi
  fi
fi

# --- 2b) App analyzes -----------------------------------------------------------
# Runs `flutter analyze` when app sources changed. The cache key covers every analyzed file, not
# only the changed ones, because one edit can break another file. Flutter is found on PATH, then
# in $FLUTTER_ROOT, then in the owner's install folder; without it the step is skipped.
# PT: Roda `flutter analyze` quando o código do app mudou. A chave do cache cobre todos os arquivos
# PT: analisados, não só os alterados, porque uma edição pode quebrar outro arquivo. O Flutter é
# PT: buscado no PATH, depois em $FLUTTER_ROOT, depois na pasta de instalação do dono; sem ele o
# PT: passo é pulado.
analyze_inputs=$(printf '%s\n' $existing | grep -E '^app/(lib/.*\.dart|test/.*\.dart|pubspec\.yaml|analysis_options\.yaml)$')
if [ -n "$analyze_inputs" ]; then
  flutter_bin=$(command -v flutter 2>/dev/null)
  [ -z "$flutter_bin" ] && [ -n "$FLUTTER_ROOT" ] && [ -x "$FLUTTER_ROOT/bin/flutter" ] \
    && flutter_bin="$FLUTTER_ROOT/bin/flutter"
  [ -z "$flutter_bin" ] && [ -x "$HOME/Documents/development/flutter/bin/flutter" ] \
    && flutter_bin="$HOME/Documents/development/flutter/bin/flutter"
  if [ -n "$flutter_bin" ]; then
    all_app=$(find app/lib app/test -name '*.dart' 2>/dev/null | sort)
    signature=$(cat $all_app app/pubspec.yaml app/analysis_options.yaml 2>/dev/null | cksum | cut -d' ' -f1)
    marker="$cache/snapledger_analyze_ok_$signature"
    if [ ! -f "$marker" ]; then
      analyze_out=$(cd app && "$flutter_bin" analyze 2>&1)
      if [ $? -eq 0 ]; then
        touch "$marker"
      else
        problems="$problems
## flutter analyze failed (app/analysis_options.yaml)
$(printf '%s\n' "$analyze_out" | grep -E ' • |rror' | head -30)"
      fi
    fi
  fi
fi

# --- 3) Security review reminder (once per change set) ------------------------
sensitive=$(printf '%s\n' $existing | grep -E \
  '^api/src/main/java/.*/(auth|shared/security|shared/config)/|^api/src/main/resources/application.*\.(properties|ya?ml)$|^api/src/main/resources/db/migration/.*(user|refresh_token)|^api/pom\.xml$|^\.env\.example$|^docker-compose\.yml$|^app/lib/core/(api|session|storage|config)/|^app/lib/features/auth/|^app/pubspec\.yaml$|^app/android/app/src/main/AndroidManifest\.xml$|^app/ios/Runner/Info\.plist$|^app/web/index\.html$')
if [ -n "$sensitive" ]; then
  signature=$(cat $sensitive | cksum | cut -d' ' -f1)
  marker="$cache/snapledger_security_asked_$signature"
  if [ ! -f "$marker" ]; then
    touch "$marker"
    problems="$problems
## Security review required
These files touch auth, security config or secrets:
$sensitive
Run the security-reviewer agent on them (pass this file list), then report its findings to the user before finishing."
  fi
fi

if [ -n "$problems" ]; then
  {
    echo "SnapLedger final checks did not pass:"
    echo "$problems"
  } >&2
  exit 2
fi
exit 0

#!/usr/bin/env bash
# Claude Code Stop hook: runs when Claude is about to finish a response.
# 1) project rules on every changed file (vs HEAD, plus untracked);
# 2) `./mvnw compile` when API sources changed (cached per content, Java 21 required);
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

# --- 3) Security review reminder (once per change set) ------------------------
sensitive=$(printf '%s\n' $existing | grep -E \
  '^api/src/main/java/.*/(auth|shared/security|shared/config)/|^api/src/main/resources/application.*\.(properties|ya?ml)$|^api/src/main/resources/db/migration/.*(user|refresh_token)|^api/pom\.xml$|^\.env\.example$|^docker-compose\.yml$')
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

#!/usr/bin/env bash
# Claude Code PostToolUse hook (Edit|Write|MultiEdit).
# Checks ONLY the file that was just edited, so feedback is immediate and cheap.
# - ERROR  -> exit 2: stderr goes back to Claude, which must fix it before moving on.
# - WARNING only -> exit 0 with JSON additionalContext: Claude sees it, nothing is blocked.
# Portable: macOS bash 3.2, no jq.

input=$(cat)
# tool_input.file_path, extracted without jq.
file=$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$file" ] && [ -f "$file" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
rel="${file#"$PWD"/}"

json_escape() {
  awk 'BEGIN { ORS = "" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, " "); print $0 "\\n" }'
}

report=""
failed=0
rules_doc="api/CLAUDE.md"

case "$rel" in
  api/*.java|api/*.properties|api/*.yml|api/*.yaml)
    report=$(bash scripts/claude/api_rules.sh "$rel")
    [ $? -ne 0 ] && failed=1
    ;;
  app/*.dart)
    rules_doc="app/CLAUDE.md"
    if [ -f scripts/claude/mvvmc_rules.sh ]; then
      report=$(bash scripts/claude/mvvmc_rules.sh "$rel")
      [ $? -ne 0 ] && failed=1
    fi
    ;;
  *) exit 0 ;;
esac

if [ "$failed" -eq 1 ]; then
  {
    echo "Project rules failed in $rel:"
    echo "$report"
    echo
    echo "Fix every ERROR now (see $rules_doc > Automatic checks). WARNINGs are informational."
  } >&2
  exit 2
fi

if [ -n "$report" ]; then
  msg=$(printf 'Project rule warnings in %s:\n%s\n' "$rel" "$report" | json_escape)
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$msg"
fi
exit 0

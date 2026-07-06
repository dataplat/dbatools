#!/bin/bash
# stop-todo-report.sh - Scan changed files for TODO/FIXME markers and block
# until resolved or explained. Bounded by the stop-guard budget so an
# intentionally-kept marker can never trap the session.
set -uo pipefail

source "$(dirname "$0")/lib-stop-guard.sh"
source "$(dirname "$0")/lib-git-changes.sh"

# Code files only; .claude/ is excluded so the hook scripts' own message
# strings (which legitimately contain these words) never self-flag.
CODE_CHANGED=$(printf '%s\n' "$CHANGED_FILES" | grep -E '\.(ps1|psm1|psd1|cs|sql|js|ts|html|go|py|sh)$' | grep -v '^\.claude/')

if [[ -z "$CODE_CHANGED" ]]; then
    stop_guard_emit ""
    exit 0
fi

TODO_REPORT=""
while IFS= read -r file; do
    [[ -z "$file" || ! -f "$file" ]] && continue
    HITS=$(grep -n -i -E '\b(TODO|FIXME|HACK|XXX|WORKAROUND)\b' "$file" 2>/dev/null | head -10)
    if [[ -n "$HITS" ]]; then
        TODO_REPORT+="### $file"$'\n'"$HITS"$'\n\n'
    fi
done <<< "$CODE_CHANGED"

if [[ -z "$TODO_REPORT" ]]; then
    stop_guard_emit ""
    exit 0
fi

stop_guard_emit "UNFINISHED WORK DETECTED — do not stop until resolved.

The following TODO/FIXME/HACK items were found in changed files.
For each one you MUST either:

  1. Resolve it now (implement the missing code), OR
  2. Tell the user exactly what remains and why it cannot be completed in this session

Do NOT silently leave TODOs behind.

${TODO_REPORT}--- End of TODO Report ---"
exit 0

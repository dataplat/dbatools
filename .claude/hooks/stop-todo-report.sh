#!/bin/bash
exit 0
# stop-todo-report.sh - Scan changed files for TODO/FIXME and block until resolved.

INPUT=$(cat)

# Prevent re-entry if stop hook is already active
if echo "$INPUT" | grep -qE '"stop_hook_active":[[:space:]]*(true)'; then
    exit 0
fi

# Get all modified/added files from git (staged + unstaged + untracked)
CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null; git diff --cached --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
CHANGED_FILES=$(echo "$CHANGED_FILES" | sort -u | grep -E '\.(ps1|psm1|psd1|cs|sql|js|ts|html|go|py|sh)$')

if [[ -z "$CHANGED_FILES" ]]; then
    exit 0
fi

# Scan for TODO/FIXME/HACK/XXX/WORKAROUND in changed files
TODO_REPORT=""
while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    HITS=$(grep -n -i -E '\b(TODO|FIXME|HACK|XXX|WORKAROUND)\b' "$file" 2>/dev/null)
    if [[ -n "$HITS" ]]; then
        TODO_REPORT+="### $file\n"
        while IFS= read -r line; do
            TODO_REPORT+="  $line\n"
        done <<< "$HITS"
        TODO_REPORT+="\n"
    fi
done <<< "$CHANGED_FILES"

if [[ -n "$TODO_REPORT" ]]; then
    HOOK_REPORT="$TODO_REPORT" python << 'PY'
import os, json, sys

report = os.environ.get("HOOK_REPORT", "")

msg = (
    "UNFINISHED WORK DETECTED — do not stop until resolved.\n\n"
    "The following TODO/FIXME/HACK items were found in changed files.\n"
    "For each one you MUST either:\n\n"
    "  1. Resolve it now (implement the missing code), OR\n\n"
    "  2. Tell the user exactly what remains and why it cannot be completed in this session\n\n"
    "Do NOT silently leave TODOs behind. Go finish them.\n\n"
    + report +
    "\n--- End of TODO Report ---"
)

sys.stdout.write(json.dumps({"decision": "block", "reason": msg}) + "\n")
PY
fi

exit 0

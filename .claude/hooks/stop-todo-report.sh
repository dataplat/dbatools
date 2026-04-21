#!/bin/bash
# stop-todo-report.sh - Scan changed files for TODO/FIXME and report with header
# Runs at Stop to surface any incomplete work left in the code.

INPUT=$(cat)

# Prevent re-entry if stop hook is already active
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [[ "$STOP_ACTIVE" == "true" ]]; then
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
    # Escape for JSON
    ESCAPED=$(echo -e "$TODO_REPORT" | jq -Rs .)
    jq -n --argjson report "$ESCAPED" '{
        decision: "block",
        reason: ("⚠️  UNFINISHED WORK DETECTED — do not stop until resolved.\n\nThe following TODO/FIXME/HACK items were found in changed files.\nFor each one you MUST either:\n\n  1. Resolve it now (implement the missing code), OR\n\n  2. If you cannot finish due to context window size or complexity, write a self-contained prompt to docs/prompts/ that a fresh Claude session can run to complete the work. The prompt MUST:\n       - Describe exactly what each TODO requires\n       - Include all relevant file paths and line numbers\n       - Use the Agent tool with specialized subagents where appropriate (e.g. psu-developer, hugo-frontend, csharp-engineer)\n       - End with an instruction to commit the completed work using conventional commits\n     Then tell the user: \"I wrote a completion prompt to docs/prompts/<filename>.md — run it in a new session to finish.\"\n\n  3. As a last resort only: explicitly tell the user what remains and why it cannot be done at all.\n\nDo NOT silently leave TODOs behind. Go finish them.\n\n" + $report + "\n--- End of TODO Report ---")
    }'
fi

exit 0

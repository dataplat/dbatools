#!/bin/bash
# stop-todo-report.sh - Scan added lines for TODO:/FIXME:/HACK: markers and block
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

# Only the lines this change adds are scanned, so a marker that already sat in
# a touched file stays quiet. Only the colon forms count, case-sensitively:
# "workaround" and "XXX" are documentation vocabulary in this codebase (SMO
# defect notes, help prose), not unfinished-work markers.
MARKER_PATTERN='\b(TODO|FIXME|HACK):'

# Prints the added lines of a tracked file as "<new line number>:<text>".
# Header lines are skipped only before the first hunk, so an added line that
# itself starts with "++" is still scanned.
added_lines() {
    git -C "$_GIT_TOPLEVEL" diff -U0 HEAD -- "$1" 2>/dev/null | awk '
        /^@@/ { inHunk = 1; match($0, /\+[0-9]+/); n = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
        !inHunk { next }
        /^\+/ { print n ":" substr($0, 2); n++ }
    '
}

TODO_REPORT=""
while IFS= read -r file; do
    [[ -z "$file" || ! -f "$_GIT_TOPLEVEL/$file" ]] && continue
    if git -C "$_GIT_TOPLEVEL" ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
        HITS=$(added_lines "$file" | grep -E "$MARKER_PATTERN" | head -10)
    else
        # Untracked file: every line is added.
        HITS=$(grep -n -E "$MARKER_PATTERN" "$_GIT_TOPLEVEL/$file" 2>/dev/null | head -10)
    fi
    if [[ -n "$HITS" ]]; then
        TODO_REPORT+="### $file"$'\n'"$HITS"$'\n\n'
    fi
done <<< "$CODE_CHANGED"

if [[ -z "$TODO_REPORT" ]]; then
    stop_guard_emit ""
    exit 0
fi

stop_guard_emit "UNFINISHED WORK DETECTED — do not stop until resolved.

The following TODO:/FIXME:/HACK: items were found in lines added to changed files.
For each one you MUST either:

  1. Resolve it now (implement the missing code), OR
  2. Tell the user exactly what remains and why it cannot be completed in this session

Do NOT silently leave TODOs behind.

${TODO_REPORT}--- End of TODO Report ---"
exit 0

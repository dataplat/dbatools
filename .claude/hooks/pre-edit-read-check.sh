#!/bin/bash
# pre-edit-read-check.sh - Block Edit/Write on files not Read in the current session.
# Write on a new (non-existent) file is allowed without prior Read.
# Clears on compaction via session-compact-reset-reads.sh.

INPUT=$(cat)

PARSED=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
print(d.get('session_id', ''))
print(d.get('tool_name', ''))
print(d.get('tool_input', {}).get('file_path', '') or d.get('tool_input', {}).get('notebook_path', ''))
" 2>/dev/null)

SESSION_ID=$(echo "$PARSED" | sed -n '1p')
TOOL_NAME=$(echo "$PARSED" | sed -n '2p')
FILE_PATH=$(echo "$PARSED" | sed -n '3p')

[[ -z "$FILE_PATH" || -z "$SESSION_ID" ]] && exit 0

# Write on a new file is allowed without prior Read
if [[ "$TOOL_NAME" == "Write" ]] && [[ ! -e "$FILE_PATH" ]]; then
    exit 0
fi

STATE_FILE="/tmp/claude-read-tracker/${SESSION_ID}.txt"

if [[ -f "$STATE_FILE" ]] && grep -qxF "$FILE_PATH" "$STATE_FILE"; then
    exit 0
fi

echo "BLOCKED: You must Read '$FILE_PATH' before using $TOOL_NAME on it." >&2
echo "" >&2
echo "Editing without reading first causes blind edits that misunderstand the" >&2
echo "surrounding code. Read the file, then retry." >&2
exit 2

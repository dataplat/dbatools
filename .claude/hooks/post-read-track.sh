#!/bin/bash
# post-read-track.sh - Record files Read in the current session.
# Paired with pre-edit-read-check.sh to enforce Read-before-Edit.
# State lives in /tmp/claude-read-tracker/<session_id>.txt

INPUT=$(cat)

PARSED=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
print(d.get('session_id', ''))
print(d.get('tool_input', {}).get('file_path', ''))
" 2>/dev/null)

SESSION_ID=$(echo "$PARSED" | sed -n '1p')
FILE_PATH=$(echo "$PARSED" | sed -n '2p')

[[ -z "$SESSION_ID" || -z "$FILE_PATH" ]] && exit 0

STATE_DIR="/tmp/claude-read-tracker"
mkdir -p "$STATE_DIR"
echo "$FILE_PATH" >> "$STATE_DIR/${SESSION_ID}.txt"
exit 0

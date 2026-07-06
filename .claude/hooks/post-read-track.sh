#!/bin/bash
# post-read-track.sh - Record files Read in the current session.
# Paired with pre-edit-read-check.sh to enforce Read-before-Edit.
# State lives in <state-root>/read-tracker/<session_id>.txt

source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

SESSION_ID=$(hook_field '.session_id')
FILE_PATH=$(hook_field '.tool_input.file_path')

[[ -z "$SESSION_ID" || -z "$FILE_PATH" ]] && exit 0

STATE_DIR="$HOOK_STATE_ROOT/read-tracker"
mkdir -p "$STATE_DIR" 2>/dev/null
hook_normalize_path "$FILE_PATH" >> "$STATE_DIR/${SESSION_ID}.txt" 2>/dev/null
printf '\n' >> "$STATE_DIR/${SESSION_ID}.txt" 2>/dev/null
exit 0

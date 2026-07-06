#!/bin/bash
# post-write-track-session-files.sh - Record files written/edited in the
# current session. The codex auto-review Stop hook reviews ONLY these files,
# so parallel sessions never review each other's work.
#
# State lives in <state-root>/session-files/<session_id>.txt (one path per line).

source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

SESSION_ID=$(hook_field '.session_id')
FILE_PATH=$(hook_field_first '.tool_input.file_path' '.tool_response.filePath')

[[ -z "$SESSION_ID" || -z "$FILE_PATH" ]] && exit 0

STATE_DIR="$HOOK_STATE_ROOT/session-files"
mkdir -p "$STATE_DIR" 2>/dev/null
printf '%s\n' "$FILE_PATH" >> "$STATE_DIR/${SESSION_ID}.txt" 2>/dev/null
exit 0

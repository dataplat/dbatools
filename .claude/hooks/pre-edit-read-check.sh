#!/bin/bash
# pre-edit-read-check.sh - Block Edit/Write on files not Read in the current session.
# Write on a new (non-existent) file is allowed without prior Read.
# Clears on compaction via session-compact-reset-reads.sh.
# Fails open when no JSON tool exists to parse the hook input.
set -uo pipefail

source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

SESSION_ID=$(hook_field '.session_id')
TOOL_NAME=$(hook_field '.tool_name')
FILE_PATH=$(hook_field_first '.tool_input.file_path' '.tool_input.notebook_path')

[[ -z "$FILE_PATH" || -z "$SESSION_ID" ]] && exit 0

# Write on a new file is allowed without prior Read. The existence check must
# use a spelling bash understands on both platforms.
if [[ "$TOOL_NAME" == "Write" ]] && [[ ! -e "$(hook_to_unix_path "$FILE_PATH")" ]]; then
    exit 0
fi

STATE_FILE="$HOOK_STATE_ROOT/read-tracker/${SESSION_ID}.txt"
NORMALIZED=$(hook_normalize_path "$FILE_PATH")

if [[ -f "$STATE_FILE" ]] && grep -qxF "$NORMALIZED" "$STATE_FILE" 2>/dev/null; then
    exit 0
fi

echo "BLOCKED: You must Read '$FILE_PATH' before using $TOOL_NAME on it." >&2
echo "" >&2
echo "Editing without reading first causes blind edits that misunderstand the" >&2
echo "surrounding code. Read the file, then retry." >&2
exit 2

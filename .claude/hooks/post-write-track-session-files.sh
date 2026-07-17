#!/bin/bash
# post-write-track-session-files.sh - Record files written/edited in the
# current session. The codex auto-review Stop hook reviews ONLY these files,
# so parallel sessions never review each other's work.
#
# State lives in <state-root>/session-files/<session_id>.txt (one path per line).
#
# Also snapshots the just-written content to SNAP_CUR (see hook_snapshot_paths).
# Paired with the pre-write baseline, this lets the Stop hook diff THIS session's
# authored change in isolation from a parallel session's edits to the same file.
# Only the "current" side is written here; the baseline is the pre-write hook's
# job, and a missing baseline makes the Stop hook fall back to a git diff — so
# we deliberately never seed a baseline from post-write content (that would make
# baseline == current and hide the change entirely).

source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

SESSION_ID=$(hook_field '.session_id')
FILE_PATH=$(hook_field_first '.tool_input.file_path' '.tool_response.filePath')

[[ -z "$SESSION_ID" || -z "$FILE_PATH" ]] && exit 0

STATE_DIR="$HOOK_STATE_ROOT/session-files"
mkdir -p "$STATE_DIR" 2>/dev/null
printf '%s\n' "$FILE_PATH" >> "$STATE_DIR/${SESSION_ID}.txt" 2>/dev/null

# Snapshot the content as this session left it (captured at write time, not read
# from disk at Stop time — so a sibling session's later edit can't bleed in).
# Scoped to exactly what the Stop hook reviews: reviewable extensions inside the
# repo (hook_is_reviewable_file), so content the reviewer never looks at (a repo
# `.env`, anything outside the project) is never copied to the temp state root.
# The per-session dir is forced 0700 and the snapshot 0600 so contents are not
# world-readable on a shared /tmp (a no-op on Windows' per-user temp).
REPO_ROOT=$(hook_to_unix_path "$(git rev-parse --show-toplevel 2>/dev/null)")
CANON=$(realpath -m "$(hook_to_unix_path "$FILE_PATH")" 2>/dev/null)
if [[ -n "$REPO_ROOT" && -n "$CANON" && "$CANON" == "$REPO_ROOT/"* && -f "$CANON" ]] \
    && hook_is_reviewable_file "$CANON" \
    && hook_snapshot_paths "$SESSION_ID" "$FILE_PATH"; then
    SNAP_DIR=$(dirname "$SNAP_CUR")
    mkdir -p "$SNAP_DIR" 2>/dev/null
    chmod 700 "$SNAP_DIR" 2>/dev/null           # private BEFORE content lands
    cp "$CANON" "$SNAP_CUR" 2>/dev/null
    chmod 600 "$SNAP_CUR" 2>/dev/null
fi

exit 0

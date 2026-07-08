#!/bin/bash
# pre-write-snapshot-baseline.sh - Capture each file's content BEFORE this
# session first writes it, so the codex Stop hook can review THIS session's
# authored delta (baseline -> what we wrote) instead of the shared working
# tree. Without this, two sessions editing the same file (e.g. both adding a
# command to dbatools.psd1) would review each other's edits and churn each
# other's clean-cache.
#
# Baseline is captured on FIRST touch only and never overwritten, so the diff
# spans the whole session's change to the file, not just the latest edit. If
# the file does not exist yet (a new file), an empty baseline is written so the
# Stop hook sees the whole file as added.
#
# Scope + privacy: ONLY the files the Stop hook actually reviews are snapshotted
# — reviewable extensions inside the repo (see hook_is_reviewable_file). This
# keeps content the reviewer never looks at (a secret in a repo `.env`, or any
# file outside the project) out of the temp state root entirely. The per-session
# snapshot dir is forced to 0700 and each snapshot to 0600 so file contents are
# not world-readable on a shared /tmp (matters on multi-user Linux; a no-op on
# Windows' per-user temp).
#
# Fails open: any missing tool (md5sum, realpath, git) just skips the snapshot
# and the Stop hook falls back to a git working-tree diff. PreToolUse never
# blocks from here.
#
# State: <state-root>/snapshots/<session_id>/<path-hash>.base   (see
# hook_snapshot_paths in lib-hook-common.sh).

source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

SESSION_ID=$(hook_field '.session_id')
FILE_PATH=$(hook_field '.tool_input.file_path')

[[ -z "$SESSION_ID" || -z "$FILE_PATH" ]] && exit 0

# Repo-only: mirror the Stop hook's own containment so we snapshot exactly the
# files it would review — nothing outside the project tree is ever copied.
REPO_ROOT=$(hook_to_unix_path "$(git rev-parse --show-toplevel 2>/dev/null)")
[[ -n "$REPO_ROOT" ]] || exit 0
CANON=$(realpath -m "$(hook_to_unix_path "$FILE_PATH")" 2>/dev/null) || exit 0
[[ -n "$CANON" && "$CANON" == "$REPO_ROOT/"* ]] || exit 0
hook_is_reviewable_file "$CANON" || exit 0   # snapshot only what the Stop hook reviews

hook_snapshot_paths "$SESSION_ID" "$FILE_PATH" || exit 0
SNAP_DIR=$(dirname "$SNAP_BASE")
mkdir -p "$SNAP_DIR" 2>/dev/null
chmod 700 "$SNAP_DIR" 2>/dev/null           # private BEFORE any content lands

# First touch only — the baseline is the state this session inherited, never a
# later edit of our own.
if [[ ! -e "$SNAP_BASE" ]]; then
    if [[ -f "$CANON" ]]; then
        cp "$CANON" "$SNAP_BASE" 2>/dev/null
    else
        : > "$SNAP_BASE" 2>/dev/null         # new file -> empty baseline
    fi
    chmod 600 "$SNAP_BASE" 2>/dev/null
fi

# Bound disk use: drop snapshots from sessions that went idle over a day ago.
# The window is generous so a long live session never loses its baselines.
find "$HOOK_STATE_ROOT/snapshots" -type f -mmin +1440 -delete 2>/dev/null

exit 0

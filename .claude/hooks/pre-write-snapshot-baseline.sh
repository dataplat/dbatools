#!/bin/bash
# pre-write-snapshot-baseline.sh - Snapshot a file's PRE-write content the first time this session
# touches it, so a Stop-gate reviewer can build a review diff WITHOUT consulting git.
#
# Why this exists: a Stop hook that asks "what did THIS session change?" must answer from its own
# records, never from `git diff HEAD` (which is global, shared, cross-session working-tree state — a
# file another session or a subagent keeps dirtying then shows as "changed" forever, re-firing an
# expensive review on every turn, even a chat-only one). post-write-track-session-files.sh already
# records WHICH files this session wrote; this PreToolUse sibling captures the missing half — the
# baseline content to diff against. Together they are the git-free equivalent of "diff vs HEAD", but
# per-session and immune to what any other session does.
#
# Fires BEFORE Write/Edit/MultiEdit, so the file on disk is still the pre-edit version. We snapshot it
# ONLY on the FIRST touch of each path this session (if <key>.base already exists we leave it), so the
# baseline stays pinned to the session-start content and a consumer always sees the FULL session
# change, not just the delta since the last edit. A file the session creates from scratch has an EMPTY
# baseline (the file doesn't exist yet) — correct: the whole new file is the change.
#
# Store: <state-root>/session-files/<session_id>.snap/<key>.base  (key = sha1 of the canonical path,
# same normalization the other trackers use). Consumers may add their own <key>.* markers beside it.
# Passive recorder: NEVER blocks a write — always exits 0.

source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

SESSION_ID=$(hook_field '.session_id')
FILE_PATH=$(hook_field '.tool_input.file_path')

[[ -z "$SESSION_ID" || -z "$FILE_PATH" ]] && exit 0

# Canonicalize the same way for every spelling of the same file (Git Bash C:\x vs /c/x included);
# realpath -m resolves ".." without requiring the file to exist yet.
RF=$(hook_to_unix_path "$FILE_PATH")
RF=$(realpath -m "$RF" 2>/dev/null) || exit 0
[[ -z "$RF" ]] && exit 0

# Only repo-contained, reviewable files are snapshotted. The baseline exists
# solely so a review gate can diff this session's code changes — a file outside
# the repo, or one no reviewer will ever diff (.env, credentials, scratch
# output), has no consumer here, and snapshotting it would only copy
# potentially sensitive content into hook state.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
REPO_ROOT=$(hook_to_unix_path "$REPO_ROOT")
[[ -z "$REPO_ROOT" ]] && exit 0
case "$(hook_normalize_path "$RF")" in
    "$(hook_normalize_path "$REPO_ROOT")"/*) ;;
    *) exit 0 ;;
esac
# Kept in lockstep with CODE_EXT_RE in stop-codex-review.sh, plus the
# dispositions ledger (force-reviewed there despite its extension).
case "$RF" in
    *.ps1|*.psm1|*.psd1|*.cs|*.sql|*.js|*.ts|*.html|*.go|*.py|*.sh|*.md) ;;
    */codex-review-dispositions.jsonl) ;;
    *) exit 0 ;;
esac

KEY=$(printf '%s' "$(hook_normalize_path "$RF")" | sha1sum 2>/dev/null | cut -d' ' -f1)
[[ -z "$KEY" ]] && exit 0

SNAP_DIR="$HOOK_STATE_ROOT/session-files/${SESSION_ID}.snap"
BASE="$SNAP_DIR/${KEY}.base"

# First touch only — never overwrite an existing baseline (keeps it at session-start content).
[[ -e "$BASE" ]] && exit 0

# Opportunistic cleanup: snapshots from long-dead sessions have no consumer.
# Seven days comfortably outlives any resumable session (a consumer treats a
# missing baseline as unknown, never as "unchanged").
find "$HOOK_STATE_ROOT/session-files" -mindepth 2 -mtime +7 -delete 2>/dev/null
find "$HOOK_STATE_ROOT/session-files" -mindepth 1 -maxdepth 1 -type d -name "*.snap" -empty -delete 2>/dev/null

mkdir -p "$SNAP_DIR" 2>/dev/null || exit 0
chmod 700 "$SNAP_DIR" 2>/dev/null

# Snapshot the pre-write content. A file that doesn't exist yet (Write creating it) gets an empty
# baseline. Write to a temp then atomically move, and mark 0600 (a review diff is derived from it).
# When the file is ABSENT at first touch, ALSO drop a <key>.baseabsent marker: an empty <key>.base alone
# cannot tell "created this session" from "existed but was empty at session start", and a consumer
# needs that distinction to decide whether a later DELETION reverts to the baseline (created-then-deleted
# -> nothing changed) or is a real change (existed-empty-then-deleted -> still a session change).
TMP=$(mktemp "${SNAP_DIR}/.base.XXXXXXXX" 2>/dev/null) || exit 0
if [[ -f "$RF" ]]; then
    cat "$RF" > "$TMP" 2>/dev/null || { rm -f "$TMP" 2>/dev/null; exit 0; }
else
    ( umask 077; : > "$SNAP_DIR/${KEY}.baseabsent" ) 2>/dev/null
fi
chmod 600 "$TMP" 2>/dev/null
mv -f "$TMP" "$BASE" 2>/dev/null || rm -f "$TMP" 2>/dev/null
exit 0

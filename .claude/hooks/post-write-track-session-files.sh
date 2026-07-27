#!/bin/bash
# post-write-track-session-files.sh - Record files written/edited in the
# current session. The codex auto-review Stop hook reviews ONLY these files,
# so parallel sessions never review each other's work.
#
# State lives in <state-root>/session-files/<session_id>.txt (one path per line).
#
# <session_id>.repos additionally records, per git repo this session writes
# into, that repo's HEAD at the session's FIRST write there:
#     <head-sha>\t<origin-url>\t<toplevel>
# The Stop hook diffs from that baseline instead of HEAD, so a window that
# commits mid-turn cannot erase its own review surface (#625).

source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

SESSION_ID=$(hook_field '.session_id')
FILE_PATH=$(hook_field_first '.tool_input.file_path' '.tool_response.filePath')

[[ -z "$SESSION_ID" || -z "$FILE_PATH" ]] && exit 0

STATE_DIR="$HOOK_STATE_ROOT/session-files"
mkdir -p "$STATE_DIR" 2>/dev/null
printf '%s\n' "$FILE_PATH" >> "$STATE_DIR/${SESSION_ID}.txt" 2>/dev/null

# Baseline bookkeeping: one git probe per NEW repo per session; writes into a
# repo already on file are a string comparison, no subprocess.
BASELINES="$STATE_DIR/${SESSION_ID}.repos"
UNIX_PATH=$(hook_to_unix_path "$FILE_PATH")
if [[ -f "$BASELINES" ]]; then
    while IFS=$'\t' read -r _sha _origin _top; do
        [[ -n "$_top" && "$UNIX_PATH" == "$_top/"* ]] && exit 0
    done < "$BASELINES"
fi
DIR=$(dirname "$UNIX_PATH")
[[ -d "$DIR" ]] || exit 0
TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
[[ -z "$TOP" ]] && exit 0
# Git Bash spells toplevels C:/... while the prefix check above saw /c/...;
# the exact-match dedup below keeps the file from growing a line per write.
if [[ -f "$BASELINES" ]] && cut -f3 "$BASELINES" 2>/dev/null | grep -qxF "$TOP"; then
    exit 0
fi
SHA=$(git -C "$TOP" rev-parse HEAD 2>/dev/null)
[[ -z "$SHA" ]] && exit 0
ORIGIN=$(git -C "$TOP" remote get-url origin 2>/dev/null)
printf '%s\t%s\t%s\n' "$SHA" "${ORIGIN:-none}" "$TOP" >> "$BASELINES" 2>/dev/null
exit 0

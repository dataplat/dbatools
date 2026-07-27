#!/bin/bash
# post-write-track-session-files.sh - Record files written/edited in the
# current session. The codex auto-review Stop hook reviews ONLY these files,
# so parallel sessions never review each other's work.
#
# State lives in <state-root>/session-files/<session_id>.txt (one path per line).
#
# <session_id>.repos additionally records, per git repo this session writes
# into, that repo's HEAD at the session's FIRST write there:
#     <head-sha>\t-\t<toplevel>
# (the middle column once carried the origin URL; it was unused and an origin
# can embed credentials, so it is a literal "-" now). The Stop hook diffs from
# that baseline instead of HEAD, so a window that commits mid-turn cannot
# erase its own review surface (#625).
#
# The .repos file is touched on EVERY tracked write, before anything else: its
# existence certifies "the current-format tracker ran", so the Stop hook can
# tell a legacy pre-baseline session (diff HEAD, say so) from a baseline that
# failed to persist (block: cannot-measure is not pass). Any persistence
# failure here exits 2, out loud - a tracker that cannot record is a blocker,
# not a no-op.

# umask precedes the source: lib-hook-common creates the state root AT SOURCE
# TIME, and creating it group/world-readable is the race this closes.
umask 077
source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

SESSION_ID=$(hook_field '.session_id')
FILE_PATH=$(hook_field_first '.tool_input.file_path' '.tool_response.filePath')

[[ -z "$SESSION_ID" || -z "$FILE_PATH" ]] && exit 0

# The state root sits under a world-writable temp dir, so trust nothing about
# it: owner-only perms, no symlinks, and refuse to write through anything that
# fails those checks rather than recording into an attacker-chosen file. The
# root itself is validated first (lib-hook-common sets the flag at creation) -
# checking only the subdir missed a symlinked PARENT, which mkdir -p follows.
if [[ -n "${HOOK_STATE_ROOT_UNSAFE:-}" ]]; then
    echo "post-write-track-session-files: $HOOK_STATE_ROOT is a symlink, missing, or not owned by this user - refusing to record session state through it" >&2
    exit 2
fi
STATE_DIR="$HOOK_STATE_ROOT/session-files"
mkdir -p "$STATE_DIR" 2>/dev/null
chmod 700 "$STATE_DIR" 2>/dev/null
if [[ -L "$STATE_DIR" || ! -d "$STATE_DIR" || ! -O "$STATE_DIR" ]]; then
    echo "post-write-track-session-files: $STATE_DIR is a symlink, missing, or not owned by this user - session writes cannot be recorded safely" >&2
    exit 2
fi
TXT="$STATE_DIR/${SESSION_ID}.txt"
BASELINES="$STATE_DIR/${SESSION_ID}.repos"
FAILMARK="$STATE_DIR/${SESSION_ID}.fail"

# Every persistence failure below leaves a durable .fail marker that the Stop
# gate blocks on. Exit 2 alone is not enough: a failed append can still leave
# an empty or partial ledger, and a ledger that undercounts reads as a small
# quiet session - the writes that failed to record are exactly the ones that
# would ship unreviewed. If even the marker cannot be written, the Stop gate's
# empty-ledger check is the remaining backstop.
persist_failure() {
    : >> "$FAILMARK" 2>/dev/null
    chmod 600 "$FAILMARK" 2>/dev/null
    echo "post-write-track-session-files: $1" >&2
    exit 2
}

if [[ -L "$TXT" || -L "$BASELINES" ]]; then
    persist_failure "session state file is a symlink - refusing to follow it"
fi
if ! : >> "$BASELINES" 2>/dev/null; then
    persist_failure "cannot create $BASELINES - the review gate cannot measure this turn"
fi
if ! printf '%s\n' "$FILE_PATH" >> "$TXT" 2>/dev/null; then
    persist_failure "cannot append to $TXT - the review gate cannot measure this turn"
fi
# A reported-successful append can still land short (disk full mid-write):
# trust the ledger only after reading the path back out of it. Any line, not
# the last one - hooks from parallel tool calls in one message can interleave.
if ! grep -qxF -- "$FILE_PATH" "$TXT" 2>/dev/null; then
    persist_failure "append to $TXT did not persist intact - the review gate cannot measure this turn"
fi
chmod 600 "$TXT" "$BASELINES" 2>/dev/null

# Baseline bookkeeping. Dedup is by EXACT git toplevel, never by path prefix:
# migration nests inside the dbatools worktree, so an ancestor-prefix match
# would suppress the nested repo's baseline and its mid-turn commits would
# fall back to a HEAD diff and vanish (review round on 637cfd04).
UNIX_PATH=$(hook_to_unix_path "$FILE_PATH")
DIR=$(dirname "$UNIX_PATH")
[[ -d "$DIR" ]] || exit 0
TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
[[ -z "$TOP" ]] && exit 0
if cut -f3 "$BASELINES" 2>/dev/null | grep -qxF "$TOP"; then
    exit 0
fi
SHA=$(git -C "$TOP" rev-parse HEAD 2>/dev/null)
if [[ -z "$SHA" ]]; then
    persist_failure "cannot read HEAD of $TOP - no baseline recorded, so the review gate will refuse to measure files there"
fi
if ! printf '%s\t-\t%s\n' "$SHA" "$TOP" >> "$BASELINES" 2>/dev/null; then
    persist_failure "baseline append failed for $TOP - the review gate will refuse to measure files there"
fi
exit 0

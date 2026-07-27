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
    # Never write through a marker that already exists as a symlink (or any
    # non-regular file): a planted link would turn this failure path into a
    # write to an attacker-chosen target. Replace it; if that fails, skip the
    # write - the Stop gate treats a lingering symlink marker as a failure too.
    if [[ -L "$FAILMARK" ]]; then
        rm -f -- "$FAILMARK" 2>/dev/null
    fi
    if [[ ! -L "$FAILMARK" ]] && [[ ! -e "$FAILMARK" || -f "$FAILMARK" ]]; then
        : >> "$FAILMARK" 2>/dev/null
        chmod 600 "$FAILMARK" 2>/dev/null
    fi
    echo "post-write-track-session-files: $1" >&2
    exit 2
}

# ledger_verify_append <ledger> <path> <pre-count> - true iff the ledger now
# holds MORE intact copies of <path> than before the append. Presence alone is
# not enough: on a re-write of the same path, an older intact occurrence would
# vouch for a new append that landed short (round 6).
ledger_verify_append() {
    local _file="$1" _path="$2" _pre="$3" _post
    _post=$(grep -cxF -- "$_path" "$_file" 2>/dev/null)
    [[ "$_post" =~ ^[0-9]+$ ]] || _post=0
    (( _post > _pre ))
}

if [[ -L "$TXT" || -L "$BASELINES" ]]; then
    persist_failure "session state file is a symlink - refusing to follow it"
fi
if ! : >> "$BASELINES" 2>/dev/null; then
    persist_failure "cannot create $BASELINES - the review gate cannot measure this turn"
fi
PRE_COUNT=$(grep -cxF -- "$FILE_PATH" "$TXT" 2>/dev/null)
[[ "$PRE_COUNT" =~ ^[0-9]+$ ]] || PRE_COUNT=0
if ! printf '%s\n' "$FILE_PATH" >> "$TXT" 2>/dev/null; then
    persist_failure "cannot append to $TXT - the review gate cannot measure this turn"
fi
# A reported-successful append can still land short (disk full mid-write):
# trust the ledger only after counting intact copies of the path - the count
# must GROW, so an older occurrence of a re-written path cannot vouch for a
# short new one. Count, not last-line: parallel tool-call hooks interleave.
if ! ledger_verify_append "$TXT" "$FILE_PATH" "$PRE_COUNT"; then
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
# First-baseline creation is serialized: two parallel hooks in one message
# can both miss the dedup check above and append DIFFERENT HEADs for one repo
# (a peer session can commit between their reads), leaving the diff base
# ambiguous. mkdir is the portable atomic claim (no flock on Git Bash); a
# lock that cannot be acquired is a persistence failure, not a skip.
BASE_LOCK="$STATE_DIR/${SESSION_ID}.baseline.lock"
_LOCKED=""
for ((_i = 0; _i < 50; _i++)); do
    if mkdir "$BASE_LOCK" 2>/dev/null; then
        _LOCKED=1
        break
    fi
    sleep 0.1
done
if [[ -z "$_LOCKED" ]]; then
    persist_failure "baseline lock $BASE_LOCK still held after 5s - cannot record a trustworthy first-write baseline for $TOP"
fi
if cut -f3 "$BASELINES" 2>/dev/null | grep -qxF "$TOP"; then
    rmdir "$BASE_LOCK" 2>/dev/null
    exit 0
fi
SHA=$(git -C "$TOP" rev-parse HEAD 2>/dev/null)
if [[ -z "$SHA" ]]; then
    rmdir "$BASE_LOCK" 2>/dev/null
    persist_failure "cannot read HEAD of $TOP - no baseline recorded, so the review gate will refuse to measure files there"
fi
if ! printf '%s\t-\t%s\n' "$SHA" "$TOP" >> "$BASELINES" 2>/dev/null; then
    rmdir "$BASE_LOCK" 2>/dev/null
    persist_failure "baseline append failed for $TOP - the review gate will refuse to measure files there"
fi
rmdir "$BASE_LOCK" 2>/dev/null
exit 0

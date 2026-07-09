#!/bin/bash
# stop-jscpd-ratchet.sh - Stop gate: block NEW copy-paste duplication.
#
# At turn end, scan the baselined roots with jscpd and compare the clones that
# touch THIS SESSION'S written files against .jscpd-baseline.json. The turn is
# blocked when it introduced duplication the baseline does not already account
# for — a brand-new clone fingerprint, an existing fingerprint spreading to a
# NEW file (a fresh copy of already-duplicated code), or an existing
# fingerprint gaining MORE copies. Duplication the baseline records is fine.
#
# Scope comes from post-write-track-session-files.sh (same as the codex review
# gate), NEVER from `git diff` — the working tree is global, shared,
# cross-session state, and another session's dirty files must not block this
# turn. The tradeoff is the same one the codex gate accepts: files changed via
# raw Bash aren't tracked, and the /precommit sweep covers those on demand.
#
# Node-only reimplementation of the retired jscpd+Python ratchet — jscpd itself
# needs node, so node is the ONLY runtime dependency and the gate runs
# identically on Git Bash and Linux (see lib-jscpd.js for how the per-platform
# jscpd binary is resolved).
#
# Opt-in per clone of the repo: dormant until .jscpd-baseline.json exists
# (create it: bash .claude/hooks/jscpd-baseline.sh). Fail-OPEN by design: a
# missing baseline, an unavailable jscpd/node, a timeout, or a parse error all
# pass silently — infrastructure trouble must never wedge a turn. Blocks are
# bounded by the stop-guard budget, so a disputed clone can never trap the
# session. Disable per session: CLAUDE_JSCPD_RATCHET=off.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib-stop-guard.sh"

if [[ "${CLAUDE_JSCPD_RATCHET:-}" == "off" ]]; then
    exit 0
fi

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
REPO_ROOT=$(hook_to_unix_path "$REPO_ROOT")
BASELINE="$REPO_ROOT/.jscpd-baseline.json"
if [[ -z "$REPO_ROOT" || ! -f "$BASELINE" ]]; then
    exit 0
fi

NODE_BIN=""
for c in node node.exe; do
    if command -v "$c" >/dev/null 2>&1; then
        NODE_BIN="$c"
        break
    fi
done
[[ -z "$NODE_BIN" ]] && exit 0

# This session's writes, recorded by post-write-track-session-files.sh. No
# session id or no tracker file means nothing was written this session.
SESSION_ID=$(hook_field '.session_id')
SESSION_STATE="$HOOK_STATE_ROOT/session-files/${SESSION_ID}.txt"
if [[ -z "$SESSION_ID" || ! -f "$SESSION_STATE" ]]; then
    stop_guard_emit ""
    exit 0
fi

# Only the source languages jscpd scans (kept in lockstep with FORMATS in
# lib-jscpd.js); .claude/ is excluded so hook work never scans itself. Files
# outside the baselined roots are harmless to pass — they appear in no clone.
# Deleted files drop out (nothing to touch), and the tracker may hold Windows
# spellings on Git Bash, so each path is canonicalized first.
CODE_CHANGED=""
TOUCH_ARGS=()
while IFS= read -r raw; do
    [[ -z "$raw" ]] && continue
    f=$(hook_to_unix_path "$raw")
    case "$f" in
        */.claude/*) continue ;;
        *.ps1|*.psm1|*.cs|*.sql) ;;
        *) continue ;;
    esac
    [[ -f "$f" ]] || continue
    TOUCH_ARGS+=(--touching "$f")
    CODE_CHANGED+="${f#"$REPO_ROOT"/}"$'\n'
done < <(sort -u "$SESSION_STATE" 2>/dev/null)

if [[ ${#TOUCH_ARGS[@]} -eq 0 ]]; then
    stop_guard_emit ""
    exit 0
fi

VERDICT=$(cd "$REPO_ROOT" && "$NODE_BIN" "$SCRIPT_DIR/lib-jscpd.js" --compare "$BASELINE" "${TOUCH_ARGS[@]}" 2>/dev/null)

STATE="${VERDICT%%|*}"
DETAIL="${VERDICT#*|}"

if [[ "$STATE" == "BLOCK" ]]; then
    stop_guard_emit "NEW COPY-PASTE DUPLICATION DETECTED — ${DETAIL} new clone(s) vs .jscpd-baseline.json in this session's written files:

$CODE_CHANGED
New duplication is not allowed (duplication the baseline already records is fine).
Fix: extract the shared logic into a private function/helper instead of copying it.
If this duplication is legitimately unavoidable, refresh the baseline and say so:

  bash .claude/hooks/jscpd-baseline.sh --force"
else
    # OK and OPEN both pass — OPEN means jscpd/baseline trouble, which fails open.
    stop_guard_emit ""
fi
exit 0

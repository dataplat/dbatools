#!/bin/bash
# lib-stop-guard.sh - Prevents infinite re-entry of Stop hooks.
#
# Uses a file-based marker tied to the transcript path. Two usage modes:
#
#   ADVISORY hooks (nudge once per session) — use the skip flag:
#       source "$(dirname "$0")/lib-stop-guard.sh"
#       if [[ "$STOP_GUARD_SKIP" == "true" ]]; then
#           exit 0
#       fi
#
#   BLOCKING hooks (enforce until satisfied) — skip the early-exit and route
#   the block through the budget so it re-fires every turn but never loops
#   forever:
#       source "$(dirname "$0")/lib-stop-guard.sh"
#       REASON=""
#       if [[ <violation> ]]; then REASON="explain the violation"; fi
#       stop_guard_emit "$REASON"
#       exit 0
#
# stop_guard_emit <reason-or-empty>:
#   - empty      -> satisfied this turn; resets the streak counter.
#   - non-empty  -> a violation. Increments a per-hook streak counter and:
#                     n <= STOP_GUARD_MAX_BLOCKS (default 3): emits the block
#                     n >  max: emits a loud advisory instead and lets the turn
#                     end, so the agent is never trapped in a Stop->work->Stop
#                     loop. The counter stays armed until the violation clears.
#
# Marker and counter files are keyed per hook per transcript and auto-clean
# after an hour (stale sessions).

if [[ -n "${_LIB_STOP_GUARD_LOADED:-}" ]]; then
    return 0
fi
_LIB_STOP_GUARD_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/lib-hook-common.sh"

stop_guard_emit() {
    local reason="${1:-}"
    local trimmed="${reason//[[:space:]]/}"

    # No transcript context: cannot budget. Fail toward enforcement — emit the
    # block verbatim, never silently swallow it.
    if [[ -z "${_MARKER_DIR:-}" || -z "${_TRANSCRIPT_HASH:-}" || -z "${_HOOK_NAME:-}" ]]; then
        [[ -n "$trimmed" ]] && emit_stop_block "$reason"
        return 0
    fi

    local counter_file="${_MARKER_DIR}/${_TRANSCRIPT_HASH}_${_HOOK_NAME}.count"

    if [[ -z "$trimmed" ]]; then
        rm -f "$counter_file" 2>/dev/null
        return 0
    fi

    local n=0
    if [[ -f "$counter_file" ]]; then
        n=$(cat "$counter_file" 2>/dev/null || echo 0)
        [[ "$n" =~ ^[0-9]+$ ]] || n=0
    fi
    n=$((n + 1))
    printf '%s' "$n" > "$counter_file" 2>/dev/null || true

    local max="${STOP_GUARD_MAX_BLOCKS:-3}"
    if (( n <= max )); then
        emit_stop_block "$reason"
        return 0
    fi

    # Budget exhausted — downgrade to advisory so the agent is never trapped.
    emit_system_message "GATE BYPASSED after ${max} blocked attempts (${_HOOK_NAME}). Allowing this turn to end so you are not stuck in a loop — the issue is NOT resolved. Fix it:

${reason}"
    return 0
}

STOP_GUARD_SKIP="false"

# Read stdin once and expose it (shared with lib-hook-common's HOOK_INPUT).
hook_read_input
_STOP_HOOK_INPUT="$HOOK_INPUT"

# Extract transcript path for session-scoped marker
_TRANSCRIPT=$(hook_field '.transcript_path')

if [[ -z "$_TRANSCRIPT" ]]; then
    # No transcript = can't track; allow but don't mark
    return 0
fi

# Derive a unique marker per hook per session
_HOOK_NAME=$(basename "${BASH_SOURCE[1]:-unknown}" .sh)
_MARKER_DIR="$HOOK_STATE_ROOT/stop-guards"
mkdir -p "$_MARKER_DIR" 2>/dev/null

_TRANSCRIPT_HASH=$(printf '%s' "$_TRANSCRIPT" | md5sum 2>/dev/null | cut -d' ' -f1)
if [[ -z "$_TRANSCRIPT_HASH" ]]; then
    return 0
fi
_MARKER_FILE="${_MARKER_DIR}/${_TRANSCRIPT_HASH}_${_HOOK_NAME}"

if [[ -f "$_MARKER_FILE" ]]; then
    STOP_GUARD_SKIP="true"
else
    touch "$_MARKER_FILE" 2>/dev/null
fi

# Clean up markers older than 1 hour (stale sessions)
find "$_MARKER_DIR" -type f -mmin +60 -delete 2>/dev/null

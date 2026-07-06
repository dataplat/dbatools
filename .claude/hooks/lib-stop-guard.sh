#!/bin/bash
exit 0
# lib-stop-guard.sh - Prevents infinite re-entry of Stop hooks.
# Uses a file-based marker tied to the transcript path. On first run,
# creates the marker and allows the hook to proceed. On subsequent runs
# (same transcript = same session), detects the marker and signals "skip."

if [[ -n "${_LIB_STOP_GUARD_LOADED:-}" ]]; then
    return 0
fi
_LIB_STOP_GUARD_LOADED=1

STOP_GUARD_SKIP="false"

# Read stdin once and expose it
if [[ -z "${_STOP_HOOK_INPUT:-}" ]]; then
    _STOP_HOOK_INPUT=$(cat)
fi

# Extract transcript path for session-scoped marker
_TRANSCRIPT=$(echo "$_STOP_HOOK_INPUT" | python -c "import sys,json; print(json.loads(sys.stdin.read()).get('transcript_path',''))" 2>/dev/null)

if [[ -z "$_TRANSCRIPT" ]]; then
    return 0
fi

# Derive a unique marker per hook per session
_HOOK_NAME=$(basename "${BASH_SOURCE[1]}" .sh)
_MARKER_DIR="/tmp/claude-stop-guards"
mkdir -p "$_MARKER_DIR"

_TRANSCRIPT_HASH=$(echo "$_TRANSCRIPT" | md5sum | cut -d' ' -f1)
_MARKER_FILE="${_MARKER_DIR}/${_TRANSCRIPT_HASH}_${_HOOK_NAME}"

if [[ -f "$_MARKER_FILE" ]]; then
    STOP_GUARD_SKIP="true"
else
    touch "$_MARKER_FILE"
fi

# Clean up markers older than 1 hour
find "$_MARKER_DIR" -type f -mmin +60 -delete 2>/dev/null

#!/bin/bash
# session-compact-reset-reads.sh - Clear the Read tracker after context compaction.
# After compaction the agent's in-context memory of what was Read is gone.
# Clearing here forces a fresh Read on every file touched post-compaction.

source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

SESSION_ID=$(hook_field '.session_id')
[[ -z "$SESSION_ID" ]] && exit 0

rm -f "$HOOK_STATE_ROOT/read-tracker/${SESSION_ID}.txt" 2>/dev/null
exit 0

#!/bin/bash
# session-compact-reset-reads.sh - Clear the Read tracker after context compaction.
# After compaction the agent's in-context memory of what was Read is gone.
# Clearing here forces a fresh Read on every file touched post-compaction.

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | python3 -c "
import sys, json
print(json.loads(sys.stdin.read()).get('session_id', ''))
" 2>/dev/null)

[[ -z "$SESSION_ID" ]] && exit 0

rm -f "/tmp/claude-read-tracker/${SESSION_ID}.txt"
exit 0

#!/bin/bash
exit 0
# stop-no-deflection.sh - Block deflection phrases that dodge bug ownership.
# Rule: every error is yours to trace and fix — not label, not defer.

source "$(dirname "$0")/lib-stop-guard.sh"
if [[ "$STOP_GUARD_SKIP" == "true" ]]; then
    exit 0
fi

TRANSCRIPT=$(echo "$_STOP_HOOK_INPUT" | python -c "
import sys, json
print(json.loads(sys.stdin.read()).get('transcript_path', ''))
" 2>/dev/null)

[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0

# Extract last assistant message from JSONL transcript
LAST_MSG=$(python - "$TRANSCRIPT" << 'PY'
import sys, json

path = sys.argv[1]
last_msg = ""
try:
    lines = open(path, encoding="utf-8", errors="replace").readlines()
except OSError:
    sys.exit(0)

for line in reversed(lines):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue
    if obj.get("role") != "assistant":
        continue
    content = obj.get("content", "")
    if isinstance(content, list):
        last_msg = "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    elif isinstance(content, str):
        last_msg = content
    if last_msg.strip():
        break

print(last_msg)
PY)

[[ -z "$LAST_MSG" ]] && exit 0

# Deflection phrases to catch
DEFLECTION_PATTERNS=(
    'pre-existing'
    'pre existing'
    'preexisting'
    'not from (my|our) changes'
    'not related to (my|our) changes'
    'outside (the |my |our )?scope'
    'out of scope'
    'out-of-scope'
    'bigger refactor'
    'larger refactor'
    'separate (refactor|effort|task|ticket|issue|PR)'
    'defer(red)? (to|for) (a )?(later|future|separate|another)'
    'address(ed)? (later|separately|in a future)'
    'beyond the scope'
    'not (my|our) (responsibility|concern)'
    'existed before'
    'was already (broken|failing|there)'
    'already existed'
    'not introduced by'
    'I did not (introduce|cause|create)'
    'this (error|bug|issue|failure|problem) (is|was) not'
    'leave (this|that|it) for (now|later|a separate)'
)

COMBINED_PATTERN=$(IFS='|'; echo "${DEFLECTION_PATTERNS[*]}")
MATCHES=$(echo "$LAST_MSG" | grep -i -o -E "$COMBINED_PATTERN" 2>/dev/null | sort -u | head -5)

[[ -z "$MATCHES" ]] && exit 0

HOOK_MATCHES="$MATCHES" python << 'PY'
import os, json, sys

matches = os.environ.get("HOOK_MATCHES", "").strip().splitlines()
match_list = "\n".join(f'  - "{m}"' for m in matches if m)

msg = (
    "DEFLECTION DETECTED — You used blame-dodging language:\n\n"
    + match_list
    + "\n\nRule: Every error is yours to trace and fix — not label, not defer.\n\n"
    "You have two options:\n"
    "1. FIX IT NOW — trace the root cause and resolve it.\n"
    "2. DOCUMENT IT PRECISELY — state the exact file path, line number, what is "
    "wrong, and the specific technical reason you cannot fix it in this session "
    "(not 'out of scope' — a real reason like 'requires PowerShell v5 feature' "
    "or 'blocked on upstream dbatools change').\n\n"
    "Do NOT use vague labels. Do NOT defer without specifics. Rewrite your response."
)
sys.stdout.write(json.dumps({"decision": "block", "reason": msg}) + "\n")
PY

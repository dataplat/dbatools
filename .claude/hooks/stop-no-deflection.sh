#!/bin/bash
# stop-no-deflection.sh - Block deflection phrases that dodge bug ownership.
# Rule: every error is yours to trace and fix — not label, not defer.
# Bounded by the stop-guard budget; fails open when no JSON tool exists to
# read the transcript.
set -uo pipefail

source "$(dirname "$0")/lib-stop-guard.sh"

TRANSCRIPT="${_TRANSCRIPT:-}"
[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0

hook_detect_parser || exit 0

# Last assistant message text. Transcript lines nest the message under
# .message (current schema) but older lines carried role/content at the top
# level — read both so a schema shift degrades instead of breaking.
last_assistant_text() {
    case "$HOOK_JSON_PARSER" in
        jq)
            jq -r '
                select((.message.role // .role // .type) == "assistant")
                | (.message.content // .content // [])
                | if type == "array" then [.[] | select(.type == "text") | .text] | join("\n")
                  elif type == "string" then .
                  else "" end
                | select((. | gsub("[[:space:]]"; "")) != "")
                | @base64' "$TRANSCRIPT" 2>/dev/null | tail -1 | base64 -d 2>/dev/null
            ;;
        python|python3|py)
            local bin=("$HOOK_JSON_PARSER")
            [[ "$HOOK_JSON_PARSER" == "py" ]] && bin=(py -3)
            "${bin[@]}" -c "
import sys, json
try:
    lines = open(sys.argv[1], encoding='utf-8', errors='replace').readlines()
except OSError:
    sys.exit(0)
for line in reversed(lines):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    msg = obj.get('message') if isinstance(obj.get('message'), dict) else None
    role = (msg or {}).get('role') or obj.get('role') or obj.get('type')
    if role != 'assistant':
        continue
    content = (msg or obj).get('content', '')
    if isinstance(content, list):
        text = '\n'.join(b.get('text', '') for b in content if isinstance(b, dict) and b.get('type') == 'text')
    elif isinstance(content, str):
        text = content
    else:
        text = ''
    if text.strip():
        sys.stdout.write(text)
        break
" "$TRANSCRIPT" 2>/dev/null
            ;;
        node)
            node -e "
const fs = require('fs');
let lines;
try { lines = fs.readFileSync(process.argv[1], 'utf8').split('\n'); } catch (e) { process.exit(0); }
for (let i = lines.length - 1; i >= 0; i--) {
    const l = lines[i].trim();
    if (!l) continue;
    let o; try { o = JSON.parse(l); } catch (e) { continue; }
    const m = (o.message && typeof o.message === 'object') ? o.message : null;
    const role = (m && m.role) || o.role || o.type;
    if (role !== 'assistant') continue;
    const c = (m || o).content;
    let t = '';
    if (Array.isArray(c)) t = c.filter(b => b && b.type === 'text').map(b => b.text || '').join('\n');
    else if (typeof c === 'string') t = c;
    if (t.trim()) { process.stdout.write(t); break; }
}
" "$TRANSCRIPT" 2>/dev/null
            ;;
    esac
}

LAST_MSG=$(last_assistant_text)
[[ -z "$LAST_MSG" ]] && exit 0

# STRONG deflection phrases: unambiguous blame-dodging — fire on their own.
STRONG_PATTERNS=(
    'not from (my|our) changes'
    'not related to (my|our) changes'
    'outside (the |my |our )?scope'
    'out of scope'
    'out-of-scope'
    'bigger refactor'
    'larger refactor'
    'separate (refactor|effort|task|ticket|issue|PR)s?\b'
    'defer(red)? (to|for) (a )?(later|future|separate|another)'
    'address(ed)? (later|separately|in a future)'
    'beyond the scope'
    'not (my|our) (responsibility|concern)'
    'was already (broken|failing|there)'
    'not introduced by'
    'I did not (introduce|cause|create)'
    'this (error|bug|issue|failure|problem) (is|was) not'
    'leave (this|that|it) for (now|later|a separate)'
)

# WEAK temporal descriptors: blame-dodging ONLY when they describe an error/failure. They also
# legitimately describe test-fixture state, config, data, and prior conditions, so they only count
# inside a sentence that ALSO carries error/failure context (per lane-A false-positive report:
# "registrations that existed before the test starts" is fixture semantics, not deflection).
WEAK_PATTERNS=(
    'pre-existing'
    'pre existing'
    'preexisting'
    'existed before'
    'already existed'
)
ERROR_CONTEXT='error|bug|failure|failed|failing|fails|broken|crash|regress|defect|fault|exception|flaky|red'

STRONG_RE=$(IFS='|'; echo "${STRONG_PATTERNS[*]}")
WEAK_RE=$(IFS='|'; echo "${WEAK_PATTERNS[*]}")

# Strong matches count anywhere in the message.
STRONG_HITS=$(printf '%s' "$LAST_MSG" | grep -i -o -E "$STRONG_RE" 2>/dev/null | sort -u)

# Weak matches count only within a sentence that also has error/failure context.
WEAK_HITS=$(printf '%s' "$LAST_MSG" \
    | tr '\n' ' ' \
    | sed -E 's/([.!?])/\1\n/g' \
    | grep -i -E "$WEAK_RE" 2>/dev/null \
    | grep -i -E "$ERROR_CONTEXT" 2>/dev/null \
    | grep -i -o -E "$WEAK_RE" 2>/dev/null | sort -u)

MATCHES=$(printf '%s\n%s\n' "$STRONG_HITS" "$WEAK_HITS" | grep -v '^[[:space:]]*$' | sort -u | head -5)

if [[ -z "$MATCHES" ]]; then
    stop_guard_emit ""
    exit 0
fi

MATCH_LIST=$(printf '%s\n' "$MATCHES" | sed 's/^/  - "/; s/$/"/')

stop_guard_emit "DEFLECTION DETECTED — You used blame-dodging language:

${MATCH_LIST}

Rule: Every error is yours to trace and fix — not label, not defer.

You have two options:
1. FIX IT NOW — trace the root cause and resolve it.
2. DOCUMENT IT PRECISELY — state the exact file path, line number, what is wrong, and the specific technical reason you cannot fix it in this session (not 'out of scope' — a real reason like 'requires PowerShell v5 feature' or 'blocked on upstream SMO change').

Do NOT use vague labels. Do NOT defer without specifics. Rewrite your response."
exit 0

#!/bin/bash
# lib-codex-review-exec.sh - codex-exec support for stop-codex-review.sh:
# the human-tailable live VIEW setup + hardening, and the JSONL
# final-message parser used as fallback when codex's -o file is empty.

if [[ -n "${_LIB_CODEX_REVIEW_EXEC_LOADED:-}" ]]; then
    return 0
fi
_LIB_CODEX_REVIEW_EXEC_LOADED=1

# codex_review_setup_livelog — sets LIVE_LOG to the fixed, human-tailable view
# path ($HOME/.codex-review.live.log), or /dev/null on any doubt.
# View security: refuse a symlink / non-regular file / foreign-owned file, and
# force 0600 on reuse. The Unix HOME-permission check is skipped on Windows
# (Git Bash), where POSIX mode bits don't reflect the real ACLs and user
# profile directories are private by default.
# Consumes (globals): CODE_FILES. Sets: LIVE_LOG.
codex_review_setup_livelog() {
    LIVE_LOG=/dev/null
    local _hp _cand _home_ok=0
    [[ -n "${HOME:-}" && -O "$HOME" && ! -L "$HOME" ]] || return 0
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*)
            _home_ok=1
            ;;
        *)
            _hp=$(stat -c '%a' "$HOME" 2>/dev/null)
            if [[ -n "$_hp" && $(( 8#$_hp & 8#22 )) -eq 0 ]]; then
                _home_ok=1
            fi
            ;;
    esac
    [[ "$_home_ok" -eq 1 ]] || return 0
    _cand="$HOME/.codex-review.live.log"
    if [[ ! -L "$_cand" ]] && { [[ ! -e "$_cand" ]] || { [[ -f "$_cand" && -O "$_cand" ]]; }; } \
       && { [[ ! -e "$_cand" ]] || chmod 0600 "$_cand" 2>/dev/null; }; then
        ( umask 077; printf '===== codex auto-review %s | effort=%s | %s =====\n' \
            "$(date '+%H:%M:%S' 2>/dev/null)" "${CLAUDE_CODEX_REVIEW_EFFORT:-xhigh}" \
            "$(printf '%s' "$CODE_FILES" | tr '\n' ' ')" > "$_cand" ) 2>/dev/null && LIVE_LOG="$_cand"
    fi
}

# codex_jsonl_final_message <jsonl-file> — prints codex's last agent message
# from its --json stream. Base64 round-trip keeps multi-line message text
# intact through the line-oriented pass. Parser-agnostic (jq/python/node).
codex_jsonl_final_message() {
    local jsonl="$1"
    [[ -f "$jsonl" ]] || return 0
    hook_detect_parser || return 0
    case "$HOOK_JSON_PARSER" in
        jq)
            local encoded
            encoded=$(jq -r '
                if .type == "item.completed" and .item.type == "agent_message" then
                    (.item.text // .item.message // empty)
                elif .type == "agent_message" then
                    (.message // .text // empty)
                else
                    empty
                end
                | select(. != null)
                | @base64
            ' "$jsonl" 2>/dev/null | tail -1)
            [[ -n "$encoded" ]] && printf '%s' "$encoded" | base64 -d 2>/dev/null
            ;;
        python|python3|py)
            local bin=("$HOOK_JSON_PARSER")
            [[ "$HOOK_JSON_PARSER" == "py" ]] && bin=(py -3)
            "${bin[@]}" -c "
import sys, json
last = ''
try:
    fh = open(sys.argv[1], encoding='utf-8', errors='replace')
except OSError:
    sys.exit(0)
for line in fh:
    line = line.strip()
    if not line:
        continue
    try:
        o = json.loads(line)
    except Exception:
        continue
    text = None
    if o.get('type') == 'item.completed' and isinstance(o.get('item'), dict) and o['item'].get('type') == 'agent_message':
        text = o['item'].get('text') or o['item'].get('message')
    elif o.get('type') == 'agent_message':
        text = o.get('message') or o.get('text')
    if text:
        last = text
sys.stdout.write(last)
" "$jsonl" 2>/dev/null
            ;;
        node)
            node -e "
const fs = require('fs');
let last = '';
let lines;
try { lines = fs.readFileSync(process.argv[1], 'utf8').split('\n'); } catch (e) { process.exit(0); }
for (const line of lines) {
    const l = line.trim();
    if (!l) continue;
    let o; try { o = JSON.parse(l); } catch (e) { continue; }
    let text = null;
    if (o.type === 'item.completed' && o.item && o.item.type === 'agent_message') text = o.item.text || o.item.message;
    else if (o.type === 'agent_message') text = o.message || o.text;
    if (text) last = text;
}
process.stdout.write(last);
" "$jsonl" 2>/dev/null
            ;;
    esac
}

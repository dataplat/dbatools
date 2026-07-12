#!/bin/bash
# lib-hook-common.sh - Shared cross-platform runtime for all dbatools Claude Code hooks.
#
# Design constraints (why this file exists):
#   * Hooks must run identically on Windows (Git Bash — Claude Code uses it
#     automatically) and Linux. No WSL required.
#   * No hard tool dependencies: jq is absent from Git for Windows, `python`
#     is absent from most modern Linux distros (only python3), and the Windows
#     Store ships a fake `python3` stub that exits nonzero. Everything here
#     probes for a WORKING tool and fails open when none exists, so a teammate
#     with a minimal environment never gets a broken session.
#   * All state lives under one temp root so cleanup is trivial.
#
# Usage:
#   source "$(dirname "$0")/lib-hook-common.sh"
#   hook_read_input                                # stdin -> $HOOK_INPUT (idempotent)
#   FILE_PATH=$(hook_field '.tool_input.file_path')
#   CMD=$(hook_field '.tool_input.command')

if [[ -n "${_LIB_HOOK_COMMON_LOADED:-}" ]]; then
    return 0
fi
_LIB_HOOK_COMMON_LOADED=1

# ---------------------------------------------------------------- state root
HOOK_STATE_ROOT="${TMPDIR:-/tmp}/claude-dbatools-hooks"
mkdir -p "$HOOK_STATE_ROOT" 2>/dev/null

# ---------------------------------------------------------------- stdin (once)
# Reads stdin exactly once, no matter how many libs/hooks ask for it.
hook_read_input() {
    if [[ -z "${HOOK_INPUT+x}" ]]; then
        HOOK_INPUT=$(cat 2>/dev/null)
    fi
}

# ---------------------------------------------------------------- JSON parser
# Detect one WORKING JSON tool. Each candidate is verified with a real parse,
# not just command -v, because the Windows Store `python3` alias is a stub
# that "exists" but cannot run scripts. Result is cached across hook
# invocations (one probe cost per machine, not per hook).
hook_detect_parser() {
    if [[ -n "${HOOK_JSON_PARSER:-}" ]]; then
        return 0
    fi
    local cache="$HOOK_STATE_ROOT/json-parser.cached" cand
    if [[ -f "$cache" ]]; then
        cand=$(cat "$cache" 2>/dev/null)
        case "$cand" in
            jq|python|python3|py|node)
                if command -v "$cand" >/dev/null 2>&1; then
                    HOOK_JSON_PARSER="$cand"
                    return 0
                fi
                ;;
        esac
    fi
    HOOK_JSON_PARSER=""
    if printf '{"a":1}' | jq -e '.a' >/dev/null 2>&1; then
        HOOK_JSON_PARSER="jq"
    elif printf '{"a":1}' | python -c "import sys,json;json.load(sys.stdin)" >/dev/null 2>&1; then
        HOOK_JSON_PARSER="python"
    elif printf '{"a":1}' | python3 -c "import sys,json;json.load(sys.stdin)" >/dev/null 2>&1; then
        HOOK_JSON_PARSER="python3"
    elif printf '{"a":1}' | py -3 -c "import sys,json;json.load(sys.stdin)" >/dev/null 2>&1; then
        HOOK_JSON_PARSER="py"
    elif printf '{"a":1}' | node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" >/dev/null 2>&1; then
        HOOK_JSON_PARSER="node"
    fi
    [[ -n "$HOOK_JSON_PARSER" ]] && printf '%s' "$HOOK_JSON_PARSER" > "$cache" 2>/dev/null
    [[ -n "$HOOK_JSON_PARSER" ]]
}

# hook_field '<dotted.path>' — extract one field from $HOOK_INPUT.
# Dotted path only (e.g. '.tool_input.file_path'). Missing field, missing
# parser, or malformed JSON all yield empty output — callers fail open.
hook_field() {
    local path="$1"
    hook_read_input
    [[ -z "$HOOK_INPUT" ]] && return 0
    hook_detect_parser || return 0
    case "$HOOK_JSON_PARSER" in
        jq)
            printf '%s' "$HOOK_INPUT" | jq -r "$path // empty" 2>/dev/null
            ;;
        python|python3|py)
            local bin=("$HOOK_JSON_PARSER")
            [[ "$HOOK_JSON_PARSER" == "py" ]] && bin=(py -3)
            printf '%s' "$HOOK_INPUT" | "${bin[@]}" -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for part in sys.argv[1].lstrip('.').split('.'):
    d = d.get(part) if isinstance(d, dict) else None
    if d is None:
        break
if d is None:
    sys.exit(0)
if isinstance(d, bool):
    sys.stdout.write('true' if d else 'false')
elif isinstance(d, str):
    sys.stdout.write(d)
else:
    sys.stdout.write(json.dumps(d))
" "$path" 2>/dev/null
            ;;
        node)
            printf '%s' "$HOOK_INPUT" | node -e "
let d;
try { d = JSON.parse(require('fs').readFileSync(0, 'utf8')); } catch (e) { process.exit(0); }
for (const p of process.argv[1].replace(/^\./, '').split('.')) {
    d = (d && typeof d === 'object') ? d[p] : undefined;
    if (d === undefined || d === null) break;
}
if (d === undefined || d === null) process.exit(0);
process.stdout.write(typeof d === 'string' ? d : JSON.stringify(d));
" "$path" 2>/dev/null
            ;;
    esac
}

# hook_field_first '<path1>' '<path2>' ... — first non-empty extraction wins.
hook_field_first() {
    local p v
    for p in "$@"; do
        v=$(hook_field "$p")
        if [[ -n "$v" ]]; then
            printf '%s' "$v"
            return 0
        fi
    done
}

# ---------------------------------------------------------------- JSON output
# json_escape <text> — escape a string for embedding inside JSON double quotes.
# Pure awk so it needs no JSON tool at all (block/system messages must be
# emittable even on machines where the parser probe failed).
json_escape() {
    printf '%s' "$1" | awk 'BEGIN{ORS=""; first=1}
    {
        gsub(/\\/, "\\\\")
        gsub(/"/, "\\\"")
        gsub(/\t/, "\\t")
        gsub(/\r/, "\\r")
        if (!first) printf "\\n"
        first = 0
        printf "%s", $0
    }'
}

# emit_deny <reason> — PreToolUse permission denial with explanation.
emit_deny() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(json_escape "$1")"
}

# emit_stop_block <reason> — Stop-hook block that forces another working turn.
emit_stop_block() {
    printf '{"decision":"block","reason":"%s"}\n' "$(json_escape "$1")"
}

# emit_system_message <text> — advisory shown in the transcript, never blocks.
emit_system_message() {
    printf '{"systemMessage":"%s"}\n' "$(json_escape "$1")"
}

# ---------------------------------------------------------------- PowerShell
# hook_find_powershell — echo the best available PowerShell host.
# Order matters: pwsh (7+, cross-platform) first, then Windows PowerShell 5.1
# (powershell.exe) so Windows boxes without pwsh still get style validation —
# Windows PowerShell also carries Windows-only modules that some dbatools
# work needs, so it is a first-class citizen here, never blocked.
hook_find_powershell() {
    local c
    for c in pwsh powershell.exe powershell; do
        if command -v "$c" >/dev/null 2>&1; then
            printf '%s' "$c"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------- paths
# hook_to_unix_path <path> — one canonical spelling for filesystem work.
# On Git Bash, tool_input paths arrive as C:\x or C:/x while git and realpath
# speak /c/x; cygpath unifies them. On Linux cygpath doesn't exist and paths
# are already fine.
hook_to_unix_path() {
    local p="${1//\\//}"
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$p" 2>/dev/null || printf '%s' "$p"
    else
        printf '%s' "$p"
    fi
}

# hook_normalize_path <path> — canonical form for path-equality bookkeeping
# (read tracker, session file tracker). Backslashes become slashes; on the
# case-insensitive Windows filesystems the whole path is lowercased so
# C:\github\X.ps1 and c:/github/x.ps1 compare equal.
hook_normalize_path() {
    local p="${1//\\//}"
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*) p=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]') ;;
    esac
    printf '%s' "$p"
}

# ---------------------------------------------------------------- review scope
# The files the codex Stop hook actually reviews: code/doc extensions (markdown
# included — docs are deliverables), PLUS the review dispositions ledger, which
# is force-included so a suppression edit is itself reviewed. Single-sourced
# here so the snapshot hooks copy EXACTLY this set — never a non-reviewable
# in-repo file (e.g. a .env) — and snapshot scope can never drift from review
# scope.
HOOK_REVIEWABLE_EXT_RE='\.(ps1|psm1|psd1|cs|sql|js|ts|html|go|py|sh|md)$'
hook_is_reviewable_file() {
    [[ "$1" =~ $HOOK_REVIEWABLE_EXT_RE ]] && return 0
    [[ "$1" == *codex-review-dispositions.jsonl ]] && return 0
    return 1
}

# ---------------------------------------------------------------- snapshots
# hook_snapshot_paths <session_id> <file_path> — set SNAP_BASE and SNAP_CUR to
# THIS session's per-file content-snapshot paths, keyed by canonical absolute
# path so the pre-write (baseline), post-write (current), and Stop (diff) hooks
# all agree on the same two files. These let the codex Stop hook diff "what this
# session first found" -> "what this session last wrote" instead of the shared
# working tree, so a parallel session's edits to the same file (e.g. two
# sessions both registering a command in dbatools.psd1) are neither reviewed
# here nor churn this session's clean-cache.
#
# Returns 1 (and leaves SNAP_BASE/SNAP_CUR empty) when the session id is empty
# or md5sum is unavailable — callers then fall back to a git working-tree diff.
hook_snapshot_paths() {
    local sid="$1" fp="$2"
    SNAP_BASE=""
    SNAP_CUR=""
    [[ -n "$sid" ]] || return 1
    command -v md5sum >/dev/null 2>&1 || return 1
    local canon key
    canon=$(realpath -m "$(hook_to_unix_path "$fp")" 2>/dev/null) || return 1
    [[ -n "$canon" ]] || return 1
    key=$(printf '%s' "$(hook_normalize_path "$canon")" | md5sum 2>/dev/null | cut -d' ' -f1)
    [[ -n "$key" ]] || return 1
    local dir="$HOOK_STATE_ROOT/snapshots/$sid"
    SNAP_BASE="$dir/$key.base"
    SNAP_CUR="$dir/$key.cur"
    return 0
}

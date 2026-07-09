#!/bin/bash
# hooks-doctor.sh - Diagnose the hook environment on this machine.
#
# Every dbatools hook degrades gracefully when a tool is missing; this script
# shows exactly what is present, what each absence disables, and how to fix
# it. Run it whenever hooks behave unexpectedly:
#
#   bash .claude/hooks/hooks-doctor.sh
set -uo pipefail

source "$(dirname "$0")/lib-hook-common.sh"

pass() { printf '  [OK]      %s\n' "$1"; }
warn() { printf '  [MISSING] %s\n' "$1"; }

echo "dbatools Claude Code hooks — environment doctor"
echo "================================================"
echo
echo "Platform: $(uname -s 2>/dev/null) | Bash: ${BASH_VERSION:-unknown}"
echo "State root: $HOOK_STATE_ROOT $( [[ -w "$HOOK_STATE_ROOT" ]] && echo '(writable)' || echo '(NOT WRITABLE — trackers and stop-guards disabled)')"
echo

echo "JSON parsing (needed by nearly every hook; first working tool wins):"
rm -f "$HOOK_STATE_ROOT/json-parser.cached" 2>/dev/null
if hook_detect_parser; then
    pass "using: $HOOK_JSON_PARSER"
else
    warn "no working jq / python / python3 / py / node found"
    echo "            -> hooks fail open: no blocking, no tracking. Install Python 3 or jq."
fi
echo

echo "PowerShell (style validation of *.ps1 writes):"
rm -f "$HOOK_STATE_ROOT/powershell.cached" 2>/dev/null
if PS_BIN=$(hook_find_powershell); then
    pass "using: $PS_BIN (verified: starts cleanly)"
    # A working fallback can mask a broken preferred host — call that out so a
    # corrupted pwsh (crashes at startup) still gets fixed instead of silently
    # paying the slower fallback on every .ps1 write.
    if [[ "$PS_BIN" != "pwsh" ]] && command -v pwsh >/dev/null 2>&1; then
        warn "pwsh is installed but FAILS TO START (corrupted install?) — using $PS_BIN instead"
        echo "            -> reinstall it: sudo apt-get install --reinstall powershell"
    fi
else
    FOUND=""
    for c in pwsh powershell.exe powershell; do
        command -v "$c" >/dev/null 2>&1 && FOUND+="$c "
    done
    if [[ -n "$FOUND" ]]; then
        warn "found ${FOUND% }— but none starts cleanly (corrupted install?)"
        echo "            -> validate-style.ps1 is skipped. Reinstall: sudo apt-get install --reinstall powershell"
    else
        warn "no pwsh / powershell.exe / powershell"
        echo "            -> validate-style.ps1 is skipped. Install PowerShell 7 (pwsh)."
    fi
fi
echo

echo "git (change detection for Stop gates):"
if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
    pass "git repo detected"
else
    warn "not a git repo or git missing -> registration/TODO/verify gates inactive"
fi
echo

echo "codex CLI (external auto-review at turn end):"
rm -f "$HOOK_STATE_ROOT/codex.cached" 2>/dev/null
if ! command -v codex >/dev/null 2>&1; then
    warn "codex not installed -> auto-review silently skipped (npm install -g @openai/codex, then codex login)"
elif hook_find_codex >/dev/null; then
    pass "codex found: $(command -v codex) (verified: starts cleanly)"
    echo "            Live view while it runs: tail -f ~/.codex-review.live.log"
    echo "            Disable per session: CLAUDE_CODEX_REVIEW=off"
else
    warn "codex is on PATH but FAILS TO START -> auto-review skipped every turn"
    echo "            -> @openai/codex ships a native binary per platform; a Windows npm install"
    echo "               seen from WSL (or vice versa) cannot run. Install one for THIS platform:"
    echo "               sudo npm install -g @openai/codex@latest   (existing ~/.codex auth is reused)"
fi
echo

echo "jscpd duplication ratchet (Stop gate, opt-in via baseline):"
NODE_BIN=""
for c in node node.exe; do
    command -v "$c" >/dev/null 2>&1 && { NODE_BIN="$c"; break; }
done
REPO_ROOT=$(hook_to_unix_path "$(git rev-parse --show-toplevel 2>/dev/null)")
if [[ -z "$NODE_BIN" ]]; then
    warn "node not found -> ratchet skipped (jscpd is a node tool)"
elif JSCPD_WHERE=$("$NODE_BIN" "$(dirname "$0")/lib-jscpd.js" --where 2>/dev/null); then
    pass "jscpd resolves: $JSCPD_WHERE"
else
    warn "no platform-matching jscpd -> ratchet skipped (bash .claude/hooks/jscpd-baseline.sh installs one to ~/.dbatools-jscpd)"
fi
if [[ -n "$REPO_ROOT" && -f "$REPO_ROOT/.jscpd-baseline.json" ]]; then
    pass "baseline present: .jscpd-baseline.json"
else
    warn "no .jscpd-baseline.json -> ratchet dormant (opt in: bash .claude/hooks/jscpd-baseline.sh)"
fi
echo

echo "Opt-outs:"
echo "  - All hooks:        .claude/settings.local.json -> {\"disableAllHooks\": true}"
echo "  - codex review:     CLAUDE_CODEX_REVIEW=off"
echo "  - verify checklist: CLAUDE_STOP_VERIFY=off"
echo "  - dup ratchet:      CLAUDE_JSCPD_RATCHET=off"
echo "  - block budget:     STOP_GUARD_MAX_BLOCKS=<n> (default 3)"

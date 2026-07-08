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
if PS_BIN=$(hook_find_powershell); then
    pass "using: $PS_BIN"
else
    warn "no pwsh / powershell.exe / powershell"
    echo "            -> validate-style.ps1 is skipped. Install PowerShell 7 (pwsh)."
fi
echo

echo "git (change detection for Stop gates):"
if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
    pass "git repo detected"
else
    warn "not a git repo or git missing -> registration/TODO/verify gates inactive"
fi
echo

echo "Authored-delta isolation (codex reviews THIS session's change, not siblings'):"
if command -v md5sum >/dev/null 2>&1; then
    pass "md5sum found -> per-session pre/post-write snapshots active"
else
    warn "md5sum missing -> codex review falls back to a git working-tree diff"
    echo "            -> parallel sessions editing the same file may review each other's edits."
fi
echo

echo "codex CLI (external auto-review at turn end):"
if command -v codex >/dev/null 2>&1; then
    pass "codex found: $(command -v codex)"
    echo "            Live view while it runs: tail -f ~/.codex-review.live.log"
    echo "            Disable per session: CLAUDE_CODEX_REVIEW=off"
else
    warn "codex not installed -> auto-review silently skipped (npm install -g @openai/codex, then codex login)"
fi
echo

echo "Opt-outs:"
echo "  - All hooks:        .claude/settings.local.json -> {\"disableAllHooks\": true}"
echo "  - codex review:     CLAUDE_CODEX_REVIEW=off"
echo "  - verify checklist: CLAUDE_STOP_VERIFY=off"
echo "  - block budget:     STOP_GUARD_MAX_BLOCKS=<n> (default 3)"

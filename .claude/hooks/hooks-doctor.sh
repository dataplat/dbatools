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

echo "codex CLI (external auto-review at turn end):"
if command -v codex >/dev/null 2>&1; then
    pass "codex found: $(command -v codex)"
    echo "            Live view while it runs: tail -f ~/.codex-review.live.log"
    echo "            Disable per session: CLAUDE_CODEX_REVIEW=off"
else
    warn "codex not installed -> auto-review silently skipped (npm install -g @openai/codex, then codex login)"
fi
echo

echo "jscpd duplication ratchet (Stop gate, opt-in via baseline):"
source "$(dirname "$0")/lib-jscpd.sh"
JSCPD_PATH=$(jscpd_locate || true)
PY_PATH=$(jscpd_find_python || true)
REPO_ROOT=$(hook_to_unix_path "$(git rev-parse --show-toplevel 2>/dev/null)")
if [[ -n "$JSCPD_PATH" ]]; then
    pass "jscpd found: $JSCPD_PATH"
else
    warn "jscpd not installed -> ratchet skipped (npm install -g jscpd)"
fi
if [[ -n "$PY_PATH" ]]; then
    pass "python for ratchet: $PY_PATH"
else
    warn "no working Python 3 -> ratchet skipped"
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
echo "  - block budget:     STOP_GUARD_MAX_BLOCKS=<n> (default 3)"

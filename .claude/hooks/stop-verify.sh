#!/bin/bash
# stop-verify.sh - Quality gate when Claude finishes a dbatools session.
# Fires ONCE per session, the first time PowerShell files have changed, and
# forces a single self-verification round. Disable per-session with
# CLAUDE_STOP_VERIFY=off.
set -uo pipefail

source "$(dirname "$0")/lib-stop-guard.sh"
source "$(dirname "$0")/lib-git-changes.sh"

if [[ "${CLAUDE_STOP_VERIFY:-}" == "off" ]]; then
    exit 0
fi

# Needs transcript context to mark "already verified" — without it, stay quiet
# rather than risk a block loop.
[[ -z "${_MARKER_DIR:-}" || -z "${_TRANSCRIPT_HASH:-}" ]] && exit 0

CODE_FILES=$(printf '%s\n' "$CHANGED_FILES" | grep -E '\.(ps1|psm1|psd1)$' | grep -v '^\.claude/')
[[ -z "$CODE_FILES" ]] && exit 0

# Own marker, created only when we actually fire — the automatic stop-guard
# marker is set on every source, which would mis-mark sessions whose first
# stop happened before any code changed.
DONE_MARKER="${_MARKER_DIR}/${_TRANSCRIPT_HASH}_stop-verify.done"
[[ -f "$DONE_MARKER" ]] && exit 0
touch "$DONE_MARKER" 2>/dev/null

emit_stop_block "QUALITY GATE — PowerShell files changed this session. Perform ALL checks below, then finish (this gate fires once per session).

## 1. SYNTAX AND IMPORT
- Check changed files for parse errors
- Confirm the module still imports: Import-Module ./dbatools.psd1 -Force
- Run changed command tests if a Pester test file exists

## 2. DBATOOLS PATTERNS
- SMO first, T-SQL only for DMVs/stored procs/version-specific logic
- Pipeline output emitted immediately — no ArrayList, no \$results = @()
- No backticks (hook-enforced); splats for 3+ params with \$splat<Purpose> naming
- Hashtable = signs vertically aligned; double quotes throughout

## 3. NEW COMMAND (if you created a public/*.ps1)
- Registered in dbatools.psd1 FunctionsToExport
- Registered in dbatools.psm1 Export-ModuleMember
- .SYNOPSIS, .DESCRIPTION, .EXAMPLE, .OUTPUTS all present
- Author: 'the dbatools team + Claude'
- Singular noun (Get-DbaDatabase not Get-DbaDatabases)

## 4. PARAMETER CHANGES (if you changed parameters)
- Parameter validation tests updated
- No callers broken by rename or removal

## 5. COMMIT MESSAGE
Must include (do CommandName) to target CI test runs.

If anything fails, fix it before finishing. If everything passes, state what you verified and finish."
exit 0

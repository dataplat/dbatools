#!/bin/bash
# stop-registration-check.sh - Verify new public/*.ps1 commands are registered.
# New dbatools commands must appear in BOTH dbatools.psd1 AND dbatools.psm1.
# Blocking gate with a bounded budget (see lib-stop-guard.sh): re-fires each
# turn until the registration is fixed, then stands down.
set -uo pipefail

source "$(dirname "$0")/lib-stop-guard.sh"
source "$(dirname "$0")/lib-git-changes.sh"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[[ -z "$REPO_ROOT" ]] && exit 0

PUBLIC_CHANGED=$(printf '%s\n' "$CHANGED_FILES" | grep -E '^public/[^/]+\.ps1$')
if [[ -z "$PUBLIC_CHANGED" ]]; then
    stop_guard_emit ""
    exit 0
fi

VIOLATIONS=""
while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    func=$(basename "$filepath" .ps1)
    if ! grep -qE "['\"]${func}['\"]" "$REPO_ROOT/dbatools.psd1" 2>/dev/null; then
        VIOLATIONS+="  ${func}: missing from dbatools.psd1 FunctionsToExport"$'\n'
    fi
    if ! grep -qF "$func" "$REPO_ROOT/dbatools.psm1" 2>/dev/null; then
        VIOLATIONS+="  ${func}: missing from dbatools.psm1 Export-ModuleMember"$'\n'
    fi
done <<< "$PUBLIC_CHANGED"

if [[ -z "$VIOLATIONS" ]]; then
    stop_guard_emit ""
    exit 0
fi

stop_guard_emit "REGISTRATION INCOMPLETE: New command(s) in public/ not registered in the manifest.

Every new dbatools command must appear in TWO places:
  1. dbatools.psd1  — FunctionsToExport array
  2. dbatools.psm1  — Export-ModuleMember section

${VIOLATIONS}
Fix both files before finishing."
exit 0

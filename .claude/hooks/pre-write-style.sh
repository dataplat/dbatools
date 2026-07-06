#!/bin/bash
# pre-write-style.sh - Cross-platform launcher for validate-style.ps1.
#
# Finds whichever PowerShell the machine has (pwsh 7+, or Windows PowerShell
# 5.1 via powershell.exe) and forwards the hook JSON to the style validator.
# Degrades gracefully: no PowerShell at all (e.g. a slim Linux container)
# means no style validation — never a broken hook.
set -uo pipefail

source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

# Cheap extension gate in bash so non-PowerShell writes never pay a
# PowerShell process startup. If no JSON parser exists the gate yields empty
# and we let the validator (which re-checks the extension itself) decide.
FILE_PATH=$(hook_field '.tool_input.file_path')
if [[ -n "$FILE_PATH" ]]; then
    case "$FILE_PATH" in
        *.ps1) ;;
        *) exit 0 ;;
    esac
fi

PS_BIN=$(hook_find_powershell) || exit 0

printf '%s' "$HOOK_INPUT" | "$PS_BIN" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(dirname "$0")/validate-style.ps1"
exit $?

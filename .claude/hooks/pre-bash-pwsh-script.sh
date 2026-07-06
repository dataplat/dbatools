#!/bin/bash
# pre-bash-pwsh-script.sh - Keep complex inline PowerShell out of Bash calls.
#
# powershell.exe (Windows PowerShell 5.1) is deliberately ALLOWED: it carries
# Windows-only modules that parts of dbatools need, and migrations depend on
# it. What gets blocked is only the quoting hazard: long or multi-line
# PowerShell passed inline via -Command/-c. Write a .ps1 (scratchpad is fine)
# and run it with -NoProfile -File instead — identical behavior on pwsh and
# powershell.exe, no escaping bugs.
set -uo pipefail

source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

COMMAND=$(hook_field '.tool_input.command')
[[ -z "$COMMAND" ]] && exit 0

# Only PowerShell invocations with an inline -Command/-c payload are of interest
printf '%s' "$COMMAND" | grep -qiE '(pwsh|powershell(\.exe)?)([[:space:]]+-[A-Za-z]+)*[[:space:]]+-(c|command)([[:space:]]|$)' || exit 0

# Short one-liners are fine; block only when quoting is likely to go wrong:
# a multi-line payload or a very long one.
LINE_COUNT=$(printf '%s\n' "$COMMAND" | wc -l | tr -d '[:space:]')
CMD_LENGTH=${#COMMAND}
if [[ "$LINE_COUNT" -le 1 && "$CMD_LENGTH" -le 300 ]]; then
    exit 0
fi

emit_deny "Long or multi-line inline PowerShell via -Command is blocked (quoting hazard between bash and PowerShell). Write the script to a .ps1 file (scratchpad is fine) and run: pwsh -NoProfile -File <script.ps1> — or powershell.exe -NoProfile -File <script.ps1> when Windows PowerShell is required."
exit 0

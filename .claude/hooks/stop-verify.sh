#!/bin/bash
exit 0
# stop-verify.sh - Quality gate when Claude finishes a dbatools session.
# Injects a self-verify reminder. Does NOT hard-block.
# Guards against re-entry via stop_hook_active flag.

INPUT=$(cat)

# Prevent infinite loops
if echo "$INPUT" | grep -qE '"stop_hook_active":[[:space:]]*(true)'; then
    exit 0
fi

# Only trigger if PowerShell files changed
CHANGED=$(git diff --name-only HEAD 2>/dev/null; git diff --cached --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
CODE_FILES=$(echo "$CHANGED" | sort -u | grep -E '\.(ps1|psm1|psd1)$')

if [[ -z "$CODE_FILES" ]]; then
    exit 0
fi

python << 'PY'
import sys, json

msg = (
    "QUALITY GATE — If you wrote or modified PowerShell code in this response, "
    "perform ALL checks below before finishing. Skip if you only answered a question.\n\n"
    "## 1. SYNTAX AND IMPORT\n"
    "- Check for parse errors: pwsh -NoProfile -Command \"& { . './public/<file.ps1>' }\"\n"
    "- Confirm module still imports: pwsh -NoProfile -Command \"Import-Module ./dbatools.psd1 -Force\"\n"
    "- Run changed command tests if Pester test file exists\n\n"
    "## 2. DBATOOLS PATTERNS\n"
    "- SMO first, T-SQL only for DMVs/stored procs/version-specific logic\n"
    "- Pipeline output emitted immediately — no ArrayList, no $results = @()\n"
    "- No backticks (hook-enforced); splats for 3+ params with $splat<Purpose> naming\n"
    "- Hashtable = signs vertically aligned; double quotes throughout\n\n"
    "## 3. NEW COMMAND (if you created a public/*.ps1)\n"
    "- [ ] Registered in dbatools.psd1 FunctionsToExport\n"
    "- [ ] Registered in dbatools.psm1 Export-ModuleMember\n"
    "- [ ] .SYNOPSIS, .DESCRIPTION, .EXAMPLE, .OUTPUTS all present\n"
    "- [ ] Author: \"the dbatools team + Claude\"\n"
    "- [ ] Singular noun (Get-DbaDatabase not Get-DbaDatabases)\n\n"
    "## 4. PARAMETER CHANGES (if you changed parameters)\n"
    "- [ ] Parameter validation tests updated\n"
    "- [ ] No callers broken by rename or removal\n\n"
    "## 5. COMMIT MESSAGE\n"
    "Must include (do CommandName) to target CI test runs.\n"
    "Example: 'Get-DbaDatabase: Add recovery model filter\\n\\n(do Get-DbaDatabase)'\n\n"
    "If anything fails, fix it before finishing."
)

sys.stdout.write(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "Stop",
        "additionalContext": msg
    }
}) + "\n")
PY

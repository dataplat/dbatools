#!/bin/bash
# stop-verify.sh - Comprehensive quality gate when Claude finishes responding
# Incorporates: doublecheck, simplify, review, verify, and completeness checks.
# Injects a reminder to self-verify. Does NOT hard-block (no infinite loops).
# Guards against re-entry via stop_hook_active flag.

INPUT=$(cat)

# Prevent infinite loops: if stop hook is already active, exit immediately
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [[ "$STOP_ACTIVE" == "true" ]]; then
    exit 0
fi

jq -n '{
    hookSpecificOutput: {
        hookEventName: "Stop",
        additionalContext: "QUALITY GATE — If you wrote or modified code in this response, perform ALL checks below before finishing. If you only answered a question or did research, skip this.\n\n## 1. VERIFY (does it work?)\n- Check for syntax errors in changed files\n- Run tests if applicable (Pester for PS, dotnet test for C#)\n- Confirm imports, dependencies, and module loading work\n- Report what works and what does not\n\n## 2. REVIEW (is it safe and correct?)\n- Logic errors and edge cases\n- Security: credential handling, injection vulnerabilities (SQL, XSS)\n- Missing validation on user input\n- Error responses must not expose stack traces\n- Destructive operations need confirmation\n- API naming contract (plural URLs, kebab-case)\n- PSU endpoints use New-ProtectedEndpoint\n\n## 3. SIMPLIFY (is it clean?)\n- Remove unnecessary complexity\n- Consolidate duplicate logic\n- Use idiomatic patterns (PowerShell best practices for .ps1)\n- Remove dead code, unused variables, unused imports\n- Do not add features or change functionality — only simplify\n\n## 4. DOUBLECHECK (final verification)\nCreate a table:\n| Claim/Item | Verified? | Notes |\n|------------|-----------|-------|\nInclude: primary functionality, tests passing, security, naming conventions.\nBe thorough and honest about what you could not verify.\n\n## 5. COMPLETENESS\n- Were ALL requested changes made?\n- Any TODO/FIXME left behind that should be resolved?\n- Files over 400 lines that need splitting?\n- OBSERVABILITY IN ACTION: If you built or modified a page displaying fleet data, does it include action capabilities (Fix Now / Schedule / Execute buttons)? Display-only pages are not acceptable unless purely audit/history.\n\nIf anything fails, fix it before finishing."
    }
}'

exit 0

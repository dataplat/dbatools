#!/usr/bin/env bash
input=$(cat)
command=$(echo "$input" | grep -oP '"command"\s*:\s*"\K[^"]*' | head -1)

if echo "$command" | grep -qP '[A-Za-z]:\\\\'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
"permissionDecisionReason":"Windows backslash paths are mangled by Git Bash. Use forward slashes instead (e.g. C:/github/LeLab/scratchpad/foo.ps1). PowerShell handles forward slashes fine on Windows."}}
EOF
  exit 0
fi

exit 0

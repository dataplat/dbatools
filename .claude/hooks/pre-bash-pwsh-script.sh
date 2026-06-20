#!/usr/bin/env bash
export LC_ALL=C.UTF-8
input=$(cat)
command=$(echo "$input" | grep -oP '"command"\s*:\s*"\K[^"]*' | head -1)

# Block powershell.exe entirely
if echo "$command" | grep -qiP '\bpowershell(\.exe)?\b'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
"permissionDecisionReason":"Do not use powershell.exe (Windows PowerShell 5.1). Write a .ps1 file and run: pwsh -NoProfile -File <script.ps1>"}}
EOF
  exit 0
fi

# Block pwsh -Command / pwsh -c
if echo "$command" | grep -qiP 'pwsh(\s+-\w+)*\s+-(c|Command)\b'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
"permissionDecisionReason":"Do not run inline PowerShell via pwsh -Command. Write the script to scratchpad/<name>.ps1 first, then execute with: pwsh -NoProfile -File scratchpad/<name>.ps1"}}
EOF
  exit 0
fi

exit 0

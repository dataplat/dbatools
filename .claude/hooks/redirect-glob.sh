#!/usr/bin/env bash
input=$(cat)
tool=$(echo "$input" | grep -oP '"tool_name"\s*:\s*"\K[^"]*' | head -1)

if [ "$tool" != "Glob" ]; then
  exit 0
fi

pattern=$(echo "$input" | grep -oP '"pattern"\s*:\s*"\K[^"]*' | head -1)
path=$(echo "$input" | grep -oP '"path"\s*:\s*"\K[^"]*' | head -1)

search_in=""
if [ -n "$path" ]; then
  search_in=" \"$path\""
fi

cat >&2 <<EOF
BLOCKED: Glob tool is unreliable on Windows (timeouts, silent failures).
Use fd via Bash instead. fd respects .gitignore and is much faster.

Your pattern was: $pattern
Equivalent fd commands:
  /c/ProgramData/chocolatey/bin/fd.exe --type f --glob '$pattern'$search_in
  /c/ProgramData/chocolatey/bin/fd.exe --type f --extension ps1$search_in
  /c/ProgramData/chocolatey/bin/fd.exe --type f 'keyword'$search_in
EOF
exit 2

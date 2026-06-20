#!/bin/bash
# pre-bash-commit-do.sh - Enforce (do CommandName) in dbatools commit messages.
# The (do ...) pattern tells dbatools CI which test suites to run.
# Without it all tests run — slow and resource-expensive.

export LC_ALL=C.UTF-8
INPUT=$(cat)

COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
print(d.get('tool_input', {}).get('command', ''))
" 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Only check git commit commands
echo "$COMMAND" | grep -qE 'git[[:space:]]+commit\b' || exit 0

# Try to extract message from -m "..." or -m '...'
MSG=$(echo "$COMMAND" | grep -oE '\-m[[:space:]]+"[^"]*"' | head -1 | sed 's/^-m[[:space:]]*"//; s/"$//')
if [[ -z "$MSG" ]]; then
    MSG=$(echo "$COMMAND" | grep -oE "\-m[[:space:]]+'[^']*'" | head -1 | sed "s/^-m[[:space:]]*'//; s/'$//")
fi

# Can't extract message (heredoc, --file, etc.) — let through
[[ -z "$MSG" ]] && exit 0

# Check for (do pattern
echo "$MSG" | grep -qE '\(do[[:space:]]+' && exit 0

cat >&2 << 'EOF'
BLOCKED: Commit message is missing the (do ...) CI targeting pattern.

dbatools CI uses (do ...) to run only the relevant test suites:
  Get-DbaDatabase: Add recovery model filter

  (do Get-DbaDatabase)

Patterns:
  Single:    (do Get-DbaDatabase)
  Wildcard:  (do *Login*)
  Multiple:  (do *Backup*, *Restore*)

Add (do <CommandName>) to your commit message and retry.
EOF
exit 2

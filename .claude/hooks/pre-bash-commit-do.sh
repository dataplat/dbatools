#!/bin/bash
# pre-bash-commit-do.sh - Enforce (do CommandName) in dbatools commit messages.
# The (do ...) pattern tells dbatools CI which test suites to run.
# Without it all tests run — slow and resource-expensive.
set -uo pipefail

source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

COMMAND=$(hook_field '.tool_input.command')
[[ -z "$COMMAND" ]] && exit 0

# Only check git commit commands
printf '%s' "$COMMAND" | grep -qE 'git[[:space:]]+commit([[:space:]]|$)' || exit 0

# Commits that reuse or amend an existing message are out of scope
if printf '%s' "$COMMAND" | grep -qE -- '--amend|--no-edit|--fixup|--squash|--reuse-message|-C[[:space:]]|-c[[:space:]]|--file|-F[[:space:]]'; then
    exit 0
fi

# The message must be visible inline to be checkable: -m "..." or a heredoc.
# A commit without either (opens an editor, reads from a file we can't see)
# passes through — fail open, CI still catches it.
printf '%s' "$COMMAND" | grep -qE -- '-m[[:space:]]|--message|<<' || exit 0

# The (do ...) pattern anywhere in the inline command text (covers -m strings
# AND heredoc bodies, which are part of the command string).
printf '%s' "$COMMAND" | grep -qE '\(do[[:space:]]+' && exit 0

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

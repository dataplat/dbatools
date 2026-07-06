#!/bin/bash
# pre-bash-guard.sh - Block destructive commands before they run.
# Replaces prevent-destructive-git.sh (same protections, portable parsing —
# the old version needed grep -P and a raw-JSON scrape that broke on Windows).
#
# Blocks: force push, reset --hard, clean -f, checkout --force, branch -D,
# rebase onto remotes, commit --amend, --no-verify, catastrophic rm.
# Everything else passes. Fails open when the command can't be parsed.
set -uo pipefail

source "$(dirname "$0")/lib-hook-common.sh"
hook_read_input

COMMAND=$(hook_field '.tool_input.command')
[[ -z "$COMMAND" ]] && exit 0

# Block git push --force and variants (-f, --force-with-lease, --force-if-includes)
if printf '%s' "$COMMAND" | grep -qiE 'git[[:space:]]+push[[:space:]]+.*([[:space:]]-f([[:space:]]|$)|--force)'; then
    emit_deny "Force push is blocked. Use regular git push instead. If you need to force push, ask the user to do it manually."
    exit 0
fi

# Block git reset --hard
if printf '%s' "$COMMAND" | grep -qiE 'git[[:space:]]+reset[[:space:]]+.*--hard'; then
    emit_deny "git reset --hard is blocked because it discards uncommitted changes. Use git stash or git checkout -- <file> instead."
    exit 0
fi

# Block git clean -f (force delete untracked files)
if printf '%s' "$COMMAND" | grep -qiE 'git[[:space:]]+clean[[:space:]]+.*-[a-zA-Z]*f'; then
    emit_deny "git clean -f is blocked because it permanently deletes untracked files. Ask the user to run it manually if needed."
    exit 0
fi

# Block git checkout with --force/-f on branches (not file restores)
if printf '%s' "$COMMAND" | grep -qiE 'git[[:space:]]+checkout[[:space:]]+(-f|--force)([[:space:]]|$)'; then
    emit_deny "git checkout --force is blocked because it discards local changes. Use git stash first, then checkout."
    exit 0
fi

# Block git branch -D (force delete)
if printf '%s' "$COMMAND" | grep -qE 'git[[:space:]]+branch[[:space:]]+.*-D([[:space:]]|$)'; then
    emit_deny "git branch -D (force delete) is blocked. Use git branch -d for safe deletion, or ask the user to force-delete manually."
    exit 0
fi

# Block git rebase on shared/remote branches (rebase with upstream refs)
if printf '%s' "$COMMAND" | grep -qiE 'git[[:space:]]+rebase[[:space:]]+.*(origin|upstream)'; then
    emit_deny "Rebasing against remote branches is blocked to prevent history rewrites. Ask the user before rebasing."
    exit 0
fi

# Block amending commits (could rewrite published history)
if printf '%s' "$COMMAND" | grep -qiE 'git[[:space:]]+commit[[:space:]]+.*--amend'; then
    emit_deny "git commit --amend is blocked because it rewrites commit history. Create a new commit instead, or ask the user to amend manually."
    exit 0
fi

# Block --no-verify (skipping hooks hides the problem instead of fixing it)
if printf '%s' "$COMMAND" | grep -qiE 'git[[:space:]]+[a-z-]+[[:space:]]+.*--no-verify'; then
    emit_deny "--no-verify is blocked. Hooks exist for a reason — fix the underlying issue instead of skipping checks."
    exit 0
fi

# Block catastrophic deletion (rm -rf on root or drive roots)
if printf '%s' "$COMMAND" | grep -qE 'rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|/\*|[A-Za-z]:/?)([[:space:]]|$)'; then
    emit_deny "Catastrophic deletion (rm on a filesystem root) is blocked."
    exit 0
fi

exit 0

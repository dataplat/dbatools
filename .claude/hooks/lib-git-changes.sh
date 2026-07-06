#!/bin/bash
exit 0
# lib-git-changes.sh - Shared helper for hooks that need changed file lists.
# Sources once, caches results. Skips gracefully if index.lock is held.

if [[ -n "${_LIB_GIT_CHANGES_LOADED:-}" ]]; then
    return 0
fi
_LIB_GIT_CHANGES_LOADED=1

CHANGED_FILES=""

# Skip if another git process holds the lock
if [[ -f "${GIT_DIR:-.git}/index.lock" ]]; then
    return 0
fi

# Single pass: staged + unstaged + untracked, deduplicated
CHANGED_FILES=$(
    {
        git diff --name-only HEAD 2>/dev/null
        git diff --cached --name-only 2>/dev/null
        git ls-files --others --exclude-standard 2>/dev/null
    } | sort -u
)

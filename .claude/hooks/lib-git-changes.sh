#!/bin/bash
# lib-git-changes.sh - Shared helper for hooks that need changed file lists.
# Sources once, caches results. Skips gracefully if index.lock is held.

if [[ -n "${_LIB_GIT_CHANGES_LOADED:-}" ]]; then
    return 0
fi
_LIB_GIT_CHANGES_LOADED=1

CHANGED_FILES=""

# Skip if git is unavailable or another git process holds the lock
if ! command -v git >/dev/null 2>&1; then
    return 0
fi
_GIT_TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$_GIT_TOPLEVEL" || -f "$_GIT_TOPLEVEL/.git/index.lock" ]]; then
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

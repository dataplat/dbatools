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

# ---------------------------------------------------------------------------
# SESSION_CHANGED_FILES — the subset of CHANGED_FILES that THIS session wrote.
#
# CHANGED_FILES above is the WHOLE working tree's divergence from HEAD. In a
# shared checkout that several sessions/lanes edit at once, that set includes
# every OTHER lane's uncommitted work, so a Stop gate keyed off it fires on
# changes the current session never made — and keeps firing every turn, even a
# chat-only one (pre-write-snapshot-baseline.sh's header states the same rule;
# stop-codex-review.sh already obeys it). A gate that asks "what did THIS
# session change?" MUST use this variable, never CHANGED_FILES.
#
# Source of truth: post-write-track-session-files.sh records every path this
# session wrote to <state-root>/session-files/<session_id>.txt. We intersect
# that with CHANGED_FILES (so a written-then-reverted file drops out) and keep
# only paths still on disk (a written-then-deleted file is nothing to verify,
# which also excludes deletions — the status-blind half of the same class).
# Fails open to EMPTY when session context is missing — matching every gate's
# "no context -> stay quiet" stance: under-firing a nudge is safe, mis-firing
# on another lane's work is the bug being killed.
# ---------------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/lib-hook-common.sh"
SESSION_CHANGED_FILES=""
_SCF_SESSION_ID=$(hook_field '.session_id' 2>/dev/null)
_SCF_LIST="$HOOK_STATE_ROOT/session-files/${_SCF_SESSION_ID}.txt"
if [[ -n "$_SCF_SESSION_ID" && -f "$_SCF_LIST" && -n "$CHANGED_FILES" ]]; then
    _SCF_REPO=$(hook_normalize_path "$(hook_to_unix_path "$_GIT_TOPLEVEL")")
    _SCF_WIN=0
    case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) _SCF_WIN=1 ;; esac
    # Canonicalize the (small) session-written set to absolute unix paths.
    # hook_normalize_path/hook_to_unix_path emit no trailing newline, so wrap
    # each result in printf '%s\n' to keep one path per line for the intersect.
    _SCF_SET=$(while IFS= read -r _scf_p; do
        [[ -z "$_scf_p" ]] && continue
        printf '%s\n' "$(hook_normalize_path "$(hook_to_unix_path "$_scf_p")")"
    done < "$_SCF_LIST" | sort -u)
    # Intersect: emit each CHANGED_FILES relpath whose absolute form was written
    # this session AND still exists on disk.
    SESSION_CHANGED_FILES=$(printf '%s\n' "$_SCF_SET" \
        | awk -v repo="$_SCF_REPO" -v win="$_SCF_WIN" '
            NR==FNR { if ($0 != "") sess[$0]=1; next }
            $0 != "" {
                key = repo "/" $0
                if (win) key = tolower(key)
                if (key in sess) print $0
            }' - <(printf '%s\n' "$CHANGED_FILES") \
        | while IFS= read -r _scf_f; do
              [[ -n "$_scf_f" && -f "$_GIT_TOPLEVEL/$_scf_f" ]] && printf '%s\n' "$_scf_f"
          done)
fi

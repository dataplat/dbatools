#!/bin/bash
# stop-codex-review.sh - Automated external code-review gate at the end of each turn.
#
# When code files changed this session AND the `codex` CLI is installed, the
# hook builds a diff of this session's uncommitted changes and hands it to
# codex with a reviewer prompt. codex returns findings and a final-line
# verdict (CLEAN | CHANGES_REQUESTED):
#
#   CHANGES_REQUESTED -> BLOCK the turn (decision:"block") so Claude must
#   address the findings; re-review next turn. CLEAN -> allow.
#
# Convergence / cost control:
#   - A per-session "clean" cache (keyed by diff hash) skips re-reviewing a
#     diff codex already approved — no wasted codex call, no spurious block.
#   - stop_guard_emit (lib-stop-guard.sh) bounds forced rounds via
#     STOP_GUARD_MAX_BLOCKS (default 3); after the budget it downgrades to an
#     advisory so the agent is never trapped in a Stop->work->Stop loop.
#   - The strike budget is PER-DIFF: when the diff changes (progress was
#     made), the streak resets so new code gets a fresh review budget.
#
# Safety:
#   - codex runs --sandbox read-only: the reviewer MUST NOT mutate the tree.
#   - Fails OPEN on any infra problem (codex absent, timeout, error, empty
#     output): a review the tool couldn't perform never blocks the turn.
#     Developers without codex installed simply never see this gate.
#   - Review output lives only under the temp root (never the repo) so a
#     review artifact can't itself become a "changed file".
#
# Scope (deliberate): reviews ONLY files THIS session wrote via
# Write/Edit/MultiEdit (tracked by post-write-track-session-files.sh) —
# parallel sessions must not review each other's edits. Code changed purely
# via Bash (sed -i, generators) is not tracked; use the /codex skill for
# those.
#
# Review memory (lib-codex-review-memory.sh):
#   * .claude/codex-review-dispositions.jsonl — audited ledger of findings
#     ruled FALSE POSITIVE; matching findings are suppressed in every future
#     review. The ledger itself is force-included in review scope, so a
#     suppression edit is judged by the reviewer before it can land silently.
#   * prior-round findings — each blocked round's review text is replayed to
#     the reviewer next round so it verifies fixes against the CURRENT diff.
#
# Env knobs:
#   CLAUDE_CODEX_REVIEW=off       - disable for the session.
#   CLAUDE_CODEX_REVIEW_TIMEOUT   - codex wall-clock seconds (default 600).
#   CLAUDE_CODEX_REVIEW_MODEL     - codex model (default gpt-5.6-sol).
#   CLAUDE_CODEX_REVIEW_EFFORT    - codex model_reasoning_effort (default high).
#   CLAUDE_CODEX_REVIEW_MAXBYTES  - max diff bytes sent (default 200000); a
#                                   larger diff is marked truncated and fails
#                                   safe toward CHANGES_REQUESTED.
#   STOP_GUARD_MAX_BLOCKS         - ceiling on forced rounds (default 3).
#
# Live view: the codex transcript streams to $HOME/.codex-review.live.log
# (0600, truncated each round) so you can WATCH this Stop hook run with
# `tail -f ~/.codex-review.live.log` — Claude Code never streams Stop-hook
# output to its UI.
set -uo pipefail

# Blocking gate: source the guard (reads stdin, sets _TRANSCRIPT_HASH/
# _MARKER_DIR/_HOOK_NAME, provides stop_guard_emit). Do NOT early-exit on
# STOP_GUARD_SKIP — this enforces every turn.
source "$(dirname "$0")/lib-stop-guard.sh"
source "$(dirname "$0")/lib-codex-review-memory.sh"
source "$(dirname "$0")/lib-codex-review-prompt.sh"
source "$(dirname "$0")/lib-codex-review-exec.sh"

# The state root lives under a world-writable temp dir; if it is a symlink or
# not ours (lib-hook-common validates at creation), every session ledger,
# clean-cache marker, and strike counter below it is attacker-writable, so
# nothing this gate reads can be trusted. Fail closed, out loud.
if [[ -n "${HOOK_STATE_ROOT_UNSAFE:-}" ]]; then
    stop_guard_emit "CODEX AUTO-REVIEW CANNOT TRUST ITS STATE: $HOOK_STATE_ROOT is a symlink, missing, or not owned by this user, so session ledgers and review markers under it cannot be trusted. Remove the hostile entry from the temp root and end the turn again."
    exit 0
fi

# Extensions worth reviewing, PLUS markdown — docs are deliverables, reviewed
# for accuracy rather than code style.
CODE_EXT_RE='\.(ps1|psm1|psd1|cs|sql|js|ts|html|go|py|sh|md)$'

SESSION_ID=$(hook_field '.session_id')

# 0. Session-state integrity precedes reviewer availability: a codex-less box
#    degrades to an advisory and allows, and that allow must never cover a
#    session whose write ledger is known-incomplete - the tracker's failure
#    marker, an empty ledger, a baseline file without its ledger, or a missing
#    tracker all mean the measurement is broken NO MATTER what reviewer is or
#    is not installed. Block on those before asking whether codex exists.
SESSION_STATE="$HOOK_STATE_ROOT/session-files/${SESSION_ID}.txt"
SESSION_BASELINES="$HOOK_STATE_ROOT/session-files/${SESSION_ID}.repos"
SESSION_FAIL="$HOOK_STATE_ROOT/session-files/${SESSION_ID}.fail"
# -L as well as -e: a marker left as a dangling symlink names a persistence
# failure just the same, and -e alone follows the link and misses it.
if [[ -n "$SESSION_ID" ]] && [[ -e "$SESSION_FAIL" || -L "$SESSION_FAIL" ]]; then
    stop_guard_emit "CODEX AUTO-REVIEW CANNOT MEASURE: the write tracker recorded a persistence failure for this session (${SESSION_ID}.fail exists), so the write ledger is incomplete regardless of its contents. Inspect $HOOK_STATE_ROOT/session-files; if this turn's work is already committed, cite those commits in a gocodex review issue for backfill, remove the marker, and end the turn again."
    exit 0
fi
if [[ -n "$SESSION_ID" && -f "$SESSION_STATE" && ! -s "$SESSION_STATE" ]]; then
    stop_guard_emit "CODEX AUTO-REVIEW CANNOT MEASURE: the write ledger ${SESSION_ID}.txt exists but is empty - a persistence failure, not a quiet session. Inspect $HOOK_STATE_ROOT/session-files; if this turn's work is already committed, cite those commits in a gocodex review issue for backfill - then end the turn again."
    exit 0
fi
if [[ -z "$SESSION_ID" || ! -f "$SESSION_STATE" ]]; then
    # No ledger can mean "the session wrote nothing" OR "the tracker that
    # records writes is gone" - and those must not read the same (#625). The
    # tracker lives beside this hook, so its presence is checkable here;
    # settings.json wiring drift is stop-checker-integrity.sh's job.
    if [[ ! -f "$(dirname "$0")/post-write-track-session-files.sh" ]]; then
        stop_guard_emit "CODEX AUTO-REVIEW CANNOT MEASURE: post-write-track-session-files.sh is missing, so 'no tracked writes' is indistinguishable from 'the write tracker is gone'. Restore the tracker (git checkout of .claude/hooks) and end the turn again."
        exit 0
    fi
    # The tracker touches .repos before appending .txt, so .repos WITHOUT .txt
    # means the tracker ran this session and the write ledger failed to
    # persist. That is partial tracker state, not a quiet session - allowing
    # it would ship exactly the writes that failed to record.
    if [[ -n "$SESSION_ID" && -e "$SESSION_BASELINES" ]]; then
        stop_guard_emit "CODEX AUTO-REVIEW CANNOT MEASURE: ${SESSION_ID}.repos exists but the write ledger ${SESSION_ID}.txt does not, so this session's writes were tracked and then lost. Inspect $HOOK_STATE_ROOT/session-files (disk full? deleted mid-turn?); if the writes are unrecoverable, cite this turn's commits in a gocodex review issue for backfill - then end the turn again."
        exit 0
    fi
fi

# 1. Availability.
#
#    The CLAUDE_CODEX_REVIEW=off opt-out that used to sit here has been REMOVED
#    (operator directive 2026-07-25). A flag an agent can set is not a guard,
#    and this one was advertised in the hook's own bypass message, which made
#    it the single easiest way to turn the reviewer off for a whole session.
#    pretooluse-bash-tamper-guard.sh now refuses attempts to set it.
#
#    codex being absent is still a degradation rather than a block: this hook
#    is copied into repos worked by people who do not have codex, and wedging
#    their session is not this campaign's call to make. But it is no longer
#    SILENT. Between 2026-07-21 and 2026-07-24 this review did not fire at all
#    for the entire fleet — the hook lived only in the code repos and the fleet
#    had moved to migration-rooted sessions — and nobody noticed for three
#    days. A skipped review that says nothing is indistinguishable from a
#    review that passed, so it says something, every turn it is skipped.
if ! hook_find_codex >/dev/null; then
    if command -v codex >/dev/null 2>&1; then
        emit_system_message "CODEX AUTO-REVIEW DID NOT RUN: codex is on PATH but cannot start on this platform (wrong-platform npm install?). This turn has NOT been adversarially reviewed. Diagnose: bash .claude/hooks/hooks-doctor.sh"
    else
        emit_system_message "CODEX AUTO-REVIEW DID NOT RUN: codex is not installed. This turn has NOT been adversarially reviewed — treat the work as unreviewed, not as approved."
    fi
    exit 0
fi

# CAMPAIGN MULTI-ROOT (migration copy): fleet sessions are rooted in the
# migration repo but edit the code repos through absolute paths. A single
# cwd-derived root silently dropped every cross-repo file from review scope --
# the gate ran and reviewed nothing (dead 2026-07-20..24, found by gomanager).
# Most-specific first: migration nests inside the dbatools worktree.
CAMPAIGN_ROOTS=(
    "/mnt/c/github/dbatools/migration"
    "/mnt/c/github/dbatools.library"
    "/mnt/c/github/dbatools"
)
# Ledger + dispute path anchor stays the session repo (migration).
REPO_ROOT="/mnt/c/github/dbatools/migration"
# codex needs read access to all three repos.
CODEX_CWD="/mnt/c/github"
# Same trees, second spelling: C:\github is also mounted as a docker-desktop
# bind mount (#625 follow-up - the literals above miss that spelling and this
# hook dropped every file a bind-rooted session wrote). The literals stay
# canonical; on a box where they do not exist, anchor to the repo carrying
# this very hook file rather than silently reviewing nothing.
if [[ ! -d "$REPO_ROOT" ]]; then
    REPO_ROOT=$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)
fi
if [[ ! -d "$CODEX_CWD" ]]; then
    CODEX_CWD=$(cd "$REPO_ROOT/.." 2>/dev/null && pwd)
fi

# A held campaign index lock defers the measurement briefly and OUT LOUD. The
# old shape - bare exit 0 on any lock - silently ate one turn's review per
# transient lock, with three fleets committing into two shared worktrees
# (#625). A lock that outlives the wait blocks: cannot-measure is not pass.
# The last scan must come AFTER the last wait: a lock cleared during the
# final sleep must read as cleared, never as a verdict one scan stale.
wait_for_index_locks() {
    LOCKED_ROOT=""
    local _try _r
    for _try in 1 2 3 4; do
        LOCKED_ROOT=""
        for _r in "${CAMPAIGN_ROOTS[@]}"; do
            [[ -f "$_r/.git/index.lock" ]] && LOCKED_ROOT="$_r"
        done
        [[ -z "$LOCKED_ROOT" ]] && return 0
        [[ "$_try" -lt 4 ]] && sleep 5
    done
    return 0
}
wait_for_index_locks
if [[ -n "$LOCKED_ROOT" ]]; then
    stop_guard_emit "CODEX AUTO-REVIEW COULD NOT MEASURE: ${LOCKED_ROOT}/.git/index.lock was still held after three 5s waits, so this turn's diff cannot be computed and no review ran. If another git process is genuinely working, end the turn again in a moment. If the lock is stale (no live git process), remove that one lock file and end the turn again."
    exit 0
fi

# 2. Scope to THIS session's writes only. The session-state integrity blocks
#    (.fail marker, empty ledger, .repos without ledger, missing tracker)
#    MOVED to step 0 so they fire before the codex availability advisory can
#    allow a broken session on a codex-less box (round 6). What remains here
#    is the quiet session.
if [[ -z "$SESSION_ID" || ! -f "$SESSION_STATE" ]]; then
    stop_guard_emit ""    # tracker intact and recorded nothing -> nothing to review
    exit 0
fi
# The dispositions ledger is force-INCLUDED despite its extension: it
# suppresses future findings, so an edit to it must always be reviewed.
SESSION_FILES=$(sort -u "$SESSION_STATE" | grep -E "$CODE_EXT_RE|codex-review-dispositions\.jsonl$")
if [[ -z "$SESSION_FILES" ]]; then
    codex_memory_clear_prev
    stop_guard_emit ""
    exit 0
fi

# campaign_file_root <realpath> - echo the campaign repo root containing the
# file. The file's OWN git toplevel decides: it must equal a literal campaign
# root, or carry a campaign origin (the same trees on another mount spelling).
# A literal-path prefix is never sufficient by itself - it let a foreign repo
# NESTED under a campaign root ride the outer repo's baseline into the review
# payload. The literal list never shrinks (see surface_mincounts); the origin
# check only widens the same scope to other mounts.
# Returns: 0 root printed / 1 not in any git repo / 2 in a non-campaign repo /
# 3 under a campaign root but unresolvable / 4 resolved only to an OUTER repo
# while this session recorded a baseline for a deeper (now deleted) nested
# repo - 3 and 4 are cannot-measure, never skip.
campaign_file_root() {
    local rf="$1" root _dir _top _origin
    _dir=$(dirname "$rf")
    # A deleted file may have taken its directory with it; walk up to the
    # nearest surviving parent so the deletion is still attributed to a repo.
    while [[ -n "$_dir" && "$_dir" != "/" && ! -d "$_dir" ]]; do
        _dir=$(dirname "$_dir")
    done
    _top=$(git -C "$_dir" rev-parse --show-toplevel 2>/dev/null)
    if [[ -z "$_top" ]]; then
        # Unresolvable but sitting under a campaign root by path: that is a
        # broken measurement, not a scratchpad file to skip.
        for root in "${CAMPAIGN_ROOTS[@]}"; do
            if [[ "$rf" == "$root/"* ]]; then return 3; fi
        done
        return 1
    fi
    # A deleted NESTED repo resolves to its outer repo: the dirname walk-up
    # lands on the surviving parent, and the outer tree never tracked the
    # nested files, so deleting a whole repo would measure as "no change".
    # If this session recorded a baseline for a deeper repo that contained
    # this file, that deeper root is the truth and it is gone -
    # cannot-measure, never skip.
    if [[ -n "${SESSION_BASELINES:-}" && -f "${SESSION_BASELINES:-}" ]]; then
        local _bsha _bmid _btop
        while IFS=$'\t' read -r _bsha _bmid _btop; do
            [[ -n "$_btop" ]] || continue
            if [[ "$_btop" != "$_top" && "$_btop" == "$_top/"* && "$rf" == "$_btop/"* ]]; then
                return 4
            fi
        done < "$SESSION_BASELINES"
    fi
    for root in "${CAMPAIGN_ROOTS[@]}"; do
        if [[ "$_top" == "$root" ]]; then printf '%s' "$_top"; return 0; fi
    done
    # Exact identity, not a suffix: *[/:]dataplat/dbatools also matched
    # https://evil.example/dataplat/dbatools.git, which would pull a foreign
    # repo's content into the review payload. Userinfo is stripped before
    # matching so an authenticated github remote still qualifies.
    _origin=$(git -C "$_top" remote get-url origin 2>/dev/null | sed 's#//[^/@]*@#//#')
    _origin="${_origin%.git}"
    case "$_origin" in
        https://github.com/dataplat/dbatools|https://github.com/dataplat/dbatools.library|https://github.com/potatoqualitee/migration|git@github.com:dataplat/dbatools|git@github.com:dataplat/dbatools.library|git@github.com:potatoqualitee/migration|ssh://github.com/dataplat/dbatools|ssh://github.com/dataplat/dbatools.library|ssh://github.com/potatoqualitee/migration)
            printf '%s' "$_top"
            return 0
            ;;
    esac
    return 2
}

# session_baseline <repo_root> - echo the HEAD recorded at this session's
# first write into that repo (post-write-track-session-files.sh), or nothing
# for session state recorded before baselines existed.
session_baseline() {
    local want="$1" _sha _origin _top
    [[ -f "$SESSION_BASELINES" ]] || return 1
    while IFS=$'\t' read -r _sha _origin _top; do
        if [[ -n "$_top" && "$_top" == "$want" ]]; then
            printf '%s' "$_sha"
            return 0
        fi
    done < "$SESSION_BASELINES"
    return 1
}

# Build CODE_FILES + PAYLOAD from the session's code files. Re-callable: the
# CLEAN path calls it again to confirm nothing changed during the
# (minutes-long) codex run before caching the approval (TOCTOU guard).
build_session_payload() {
    # Re-derive the file list from the ledger on EVERY call: the post-review
    # TOCTOU recheck must see writes tracked while the reviewer was running -
    # reusing the list captured before the review let a newly tracked file
    # ride out on the pre-review approval (round 6).
    SESSION_FILES=$(sort -u "$SESSION_STATE" | grep -E "$CODE_EXT_RE|codex-review-dispositions\.jsonl$")
    CODE_FILES=""
    PAYLOAD=""
    DROPPED=0
    MEASURED=0
    MEASURE_FAIL=""
    LEGACY_NOTE=""
    local f rf spec d file_root root_unix rel base
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        # Canonicalize before the containment check: a traversal path must not
        # be read into the prompt. -m resolves ".." without requiring the file
        # to exist (deleted files must still resolve).
        rf=$(realpath -m "$(hook_to_unix_path "$f")" 2>/dev/null) || continue
        [[ -n "$rf" ]] || continue
        file_root=$(campaign_file_root "$rf")
        case $? in
            1) continue ;;                          # not in any git repo (scratchpad, memory) - not code under review
            2) DROPPED=$((DROPPED+1)); continue ;;  # a git repo outside the campaign - counted, never silent
            3) MEASURE_FAIL+="$rf (under a campaign root but git cannot resolve its repo)"$'\n'; continue ;;
            4) MEASURE_FAIL+="$rf (its recorded repo is gone - the path resolves only to the outer repo, which cannot see a nested deletion)"$'\n'; continue ;;
        esac
        # rf is POSIX (hook_to_unix_path) but file_root comes from git
        # rev-parse, which under Git-for-Windows answers C:/... - the prefix
        # never matched, rel stayed absolute, and every pathspec was rejected
        # with "Invalid path '/c'", blocking review of every file (#789).
        root_unix=$(hook_to_unix_path "$file_root")
        rel="${rf#"$root_unix"/}"
        # Literal, repo-relative pathspec: git pathspecs glob by default, so a
        # file named e.g. `*.ps1` could otherwise pull unrelated files in.
        spec=":(literal)${rel}"
        # Diff from the session's first-write baseline, not HEAD: a window
        # that commits mid-turn must not erase its own review surface - that
        # was #625's main hole. HEAD only for legacy session state recorded
        # before baselines existed.
        base=$(session_baseline "$file_root")
        if [[ -n "$base" ]]; then
            if ! git -C "$file_root" cat-file -e "${base}^{commit}" 2>/dev/null; then
                MEASURE_FAIL+="$rf (recorded baseline $base is not a commit in $file_root)"$'\n'
                continue
            fi
        elif [[ -f "$SESSION_BASELINES" ]]; then
            # A ledger that exists but lacks this repo means the tracker
            # failed to record the first write here; diffing HEAD instead
            # would let a mid-turn commit vanish. Cannot-measure, not pass.
            MEASURE_FAIL+="$rf (session baseline ledger has no entry for $file_root)"$'\n'
            continue
        else
            base="HEAD"
        fi
        d=$(git -C "$file_root" diff --no-color "$base" -- "$spec" 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            MEASURE_FAIL+="$rf (git diff against $base failed in $file_root)"$'\n'
            continue
        fi
        # For an untracked, still-present file the tree diff yields nothing;
        # fall back to --no-index so its full content is reviewed. --no-index
        # exits 0 for identical, 1 for a real diff (the normal case here);
        # anything higher is a failed measurement, not an empty one.
        if [[ -z "$d" && -f "$rf" ]] && ! git -C "$file_root" ls-files --error-unmatch -- "$spec" >/dev/null 2>&1; then
            d=$(cd "$file_root" && git diff --no-index --no-color -- /dev/null "$rel" 2>/dev/null)
            _ni_rc=$?
            if (( _ni_rc > 1 )); then
                MEASURE_FAIL+="$rf (git diff --no-index exited $_ni_rc)"$'\n'
                continue
            fi
        fi
        if [[ -z "$d" && "$base" == "HEAD" ]] && git -C "$file_root" ls-files --error-unmatch -- "$spec" >/dev/null 2>&1; then
            LEGACY_NOTE="This session predates turn-start baselines and a tracked file matched HEAD exactly; if this session committed that file mid-turn, its diff was NOT reviewed - cite the commit in a gocodex review issue for backfill."
        fi
        MEASURED=$((MEASURED+1))
        [[ -z "$d" ]] && continue                        # measured: no net change vs baseline
        CODE_FILES+="$(basename "$file_root")/${rel}"$'\n'
        PAYLOAD+="$d"$'\n'
    done <<< "$SESSION_FILES"
}

# 3. Build the changed-file list + a bounded diff payload.
build_session_payload
DROPPED_NOTE=""
if (( DROPPED > 0 )); then
    DROPPED_NOTE="codex auto-review: ${DROPPED} tracked file(s) sit in a non-campaign git repo and were NOT reviewed."
fi
# Cannot-measure is not pass (#625): any git failure over a session file
# blocks BEFORE the codex call - a CLEAN verdict over a partial diff would
# bless exactly the files that failed to measure.
if [[ -n "$MEASURE_FAIL" ]]; then
    stop_guard_emit "CODEX AUTO-REVIEW COULD NOT MEASURE this turn's changes, so no review ran and the turn is not approvable:

$MEASURE_FAIL
Fix the measurement (stale baseline, dead repo path). If this session's work is already committed and the state is unrecoverable, cite those commits in a gocodex review issue so the backfill covers them - then end the turn again."
    exit 0
fi
if [[ -z "$PAYLOAD" ]]; then
    # Distinguish "measured: nothing changed" from silence - an empty payload
    # over a non-empty write ledger was #625's original disguise.
    EMPTY_NOTE=""
    if (( MEASURED > 0 )); then
        EMPTY_NOTE="codex auto-review: ${MEASURED} session file(s) show no net change against their turn-start baseline - nothing to review."
    fi
    [[ -n "$LEGACY_NOTE" ]] && EMPTY_NOTE="${EMPTY_NOTE} ${LEGACY_NOTE}"
    [[ -n "$DROPPED_NOTE" ]] && EMPTY_NOTE="${EMPTY_NOTE} ${DROPPED_NOTE}"
    [[ -n "$EMPTY_NOTE" ]] && emit_system_message "$EMPTY_NOTE"
    codex_memory_clear_prev
    stop_guard_emit ""
    exit 0
fi

# Convergence hash is taken from the FULL diff BEFORE any truncation, PLUS
# the scope state (file list, dropped count, legacy gap): an approval keyed on
# the diff alone would transfer to a later turn whose payload matches but
# whose scope shifted - a newly tracked foreign-repo file or a legacy
# measurement gap is reviewable state, not noise.
payload_scope_hash() {
    printf '%s\n--scope--\n%s\n%s\n%s' "$PAYLOAD" "$CODE_FILES" "$DROPPED" "$LEGACY_NOTE" | sha256sum | cut -d' ' -f1
}
PAYLOAD_HASH=$(payload_scope_hash)

# Bound the prompt, but NEVER silently: a CLEAN verdict on a truncated diff
# would bless unseen hunks. Mark truncation so the verdict guard in step 8
# fails safe toward CHANGES_REQUESTED instead.
PAYLOAD_MAX=${CLAUDE_CODEX_REVIEW_MAXBYTES:-200000}
TRUNCATED=""
if (( ${#PAYLOAD} > PAYLOAD_MAX )); then
    OMITTED=$(( ${#PAYLOAD} - PAYLOAD_MAX ))
    PAYLOAD=$(printf '%s' "$PAYLOAD" | head -c "$PAYLOAD_MAX")
    TRUNCATED=$'\n\n[... DIFF TRUNCATED: '"$OMITTED"$' more bytes not shown. Unseen changes may contain defects -- do NOT return CLEAN; return CHANGES_REQUESTED and ask for a smaller change set. ...]'
fi

# 4. Convergence + cost guards (need transcript context for keyed markers).
CLEAN_FILE=""
if [[ -n "${_MARKER_DIR:-}" && -n "${_TRANSCRIPT_HASH:-}" ]]; then
    CLEAN_FILE="${_MARKER_DIR}/${_TRANSCRIPT_HASH}_codex-review.clean"
    COUNT_FILE="${_MARKER_DIR}/${_TRANSCRIPT_HASH}_${_HOOK_NAME}.count"

    # Already approved this exact diff+scope? Don't re-spend a codex call or
    # re-block - but the cached allow must not swallow the scope warnings,
    # which describe files the approval does NOT cover.
    if [[ -f "$CLEAN_FILE" && "$(cat "$CLEAN_FILE" 2>/dev/null)" == "$PAYLOAD_HASH" ]]; then
        [[ -n "$DROPPED_NOTE" ]] && emit_system_message "$DROPPED_NOTE"
        [[ -n "$LEGACY_NOTE" ]] && emit_system_message "$LEGACY_NOTE"
        codex_memory_clear_prev
        stop_guard_emit ""
        exit 0
    fi

    # Per-diff budget: if the diff changed since the streak started, reset it.
    LASTHASH_FILE="${_MARKER_DIR}/${_TRANSCRIPT_HASH}_codex-review.lasthash"
    if [[ ! -f "$LASTHASH_FILE" || "$(cat "$LASTHASH_FILE" 2>/dev/null)" != "$PAYLOAD_HASH" ]]; then
        rm -f "$COUNT_FILE" 2>/dev/null
        printf '%s' "$PAYLOAD_HASH" > "$LASTHASH_FILE" 2>/dev/null
    fi

    # The per-diff bypass that used to live here has been REMOVED (operator
    # directive 2026-07-25). It let the turn end after STOP_GUARD_MAX_BLOCKS
    # rounds with the message "gate bypassed ... this is NOT an approval",
    # which is precisely a check that could not fail: the work shipped, the
    # findings stayed unresolved, and the only trace was one advisory line in a
    # transcript nobody re-reads. Four rounds of hitting Stop was the entire
    # cost of ignoring the reviewer.
    #
    # Unresolved findings now keep blocking. The way out is to FIX them, or -
    # if they are wrong - to record a disposition in the ledger
    # (codex-review-dispositions.jsonl), which is a reviewed, durable, and
    # auditable act rather than an invisible one.
    :

    # 4a. WHO PAYS FOR THE ROUND (operator directive 2026-08-08: "fix it so that
    # it runs once then you initiate the recheck").
    #
    # COVERAGE IS UNCHANGED and this is not the removed bypass. A turn still
    # cannot end without a CLEAN verdict for THIS payload hash; the block below
    # is lifted by nothing except that verdict or a ledger disposition. What
    # moves is only WHEN the codex call is spent.
    #
    # Why it needed to move: the payload is cumulative - every file the session
    # has ever written, diffed from its turn-start baseline, and committing does
    # not shrink it. So an automatic round on every Stop re-reviews the entire
    # session each turn and keeps surfacing a fresh batch out of text that was
    # already there. Measured 2026-08-08: seven rounds, each finding real but
    # DIFFERENT defects, none of them a failure to converge - the ceiling read
    # that as a non-converging turn and halted the session.
    #
    # RECHECK_FILE is agent-settable deliberately. It can only cause a review to
    # RUN; there is no marker anywhere that makes one not run, and none that
    # clears a finding. An agent-settable "review me now" is not the thing the
    # no-agent-override rule forbids.
    AUTOSPENT_FILE="${_MARKER_DIR}/${_TRANSCRIPT_HASH}_codex-review.autospent"
    RECHECK_FILE="${_MARKER_DIR}/${_TRANSCRIPT_HASH}_codex-review.recheck"
    if [[ -f "$AUTOSPENT_FILE" ]]; then
        if [[ -f "$RECHECK_FILE" ]]; then
            # Consume it BEFORE the review, and prove it is gone. A marker that
            # survives its round is not a wasted check - it silently restores
            # automatic reviews for the rest of the session, which is the whole
            # cost this step exists to bound. Unverified marker I/O is how the
            # budget quietly stops existing.
            rm -f "$RECHECK_FILE" 2>/dev/null
            if [[ -e "$RECHECK_FILE" ]]; then
                stop_guard_emit "CODEX AUTO-REVIEW CANNOT BOUND ITS ROUNDS: the recheck marker

  $RECHECK_FILE

could not be removed, so the review it buys would be bought again on every
following turn. Delete it by hand, or fix whatever is holding it (permissions, a
directory that is not yours), and end the turn again."
                exit 0
            fi
        else
            stop_guard_emit "CODEX AUTO-REVIEW: this session already spent its automatic round, and the
current change set has no CLEAN verdict - so the turn cannot end yet. No codex
call was made this time and none will be until you ask, so this block is free.

Finish the work. When the tree is how you want it reviewed, ask for the review
and end the turn again:

  touch \"$RECHECK_FILE\"

The next Stop then runs a full review of the current diff. For a deeper read of
a specific plan or change, run /reviewme yourself - that is a separate reviewer
and it does not consume this budget.

Nothing here suppresses a finding: the only things that release the turn are a
CLEAN verdict for the current diff or a disposition in
.claude/codex-review-dispositions.jsonl."
            exit 0
        fi
    fi
fi

# 4b. Review memory: standing rejections from the repo ledger + the prior
#     blocked round's findings. Loaded BEFORE the nonce so the uniqueness
#     scan can cover both.
codex_memory_load_dispositions "$REPO_ROOT"
codex_memory_load_prev

# 5. Reviewer prompt: one-time-nonce fences around the diff, filenames, and
#    memory sections; strict final-line verdict contract. Sets NONCE + PROMPT.
codex_review_build_prompt

# 6. Run codex read-only. Two outputs, deliberately decoupled:
#      * REVIEW (what the gate parses) comes from per-run mktemp captures —
#        codex's authoritative final message via -o, with its JSONL stdout as
#        fallback — so a prior round's or concurrent hook's output can never
#        decide THIS run.
#      * The live VIEW (~/.codex-review.live.log) is a best-effort mirror for
#        a human tail -f; its failure can never corrupt the verdict.
#      * --disable hooks: a repo-defined codex hook would run arbitrary
#        commands outside the read-only sandbox, and its trust prompt hangs
#        headless runs. The reviewer needs no hooks, so none are loaded.
codex_review_setup_livelog

OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-review-out.XXXXXXXX" 2>/dev/null) || OUT_FILE=/dev/null
RUN_LOG=$(mktemp "${TMPDIR:-/tmp}/codex-review.XXXXXXXX" 2>/dev/null) || RUN_LOG=/dev/null

printf '%s' "$PROMPT" | timeout "${CLAUDE_CODEX_REVIEW_TIMEOUT:-600}" codex exec \
    --json \
    -C "$CODEX_CWD" \
    --skip-git-repo-check \
    --disable hooks \
    --sandbox read-only \
    --ignore-user-config \
    --ephemeral \
    --color never \
    --model "${CLAUDE_CODEX_REVIEW_MODEL:-gpt-5.6-sol}" \
    -o "$OUT_FILE" \
    -c model_reasoning_effort="${CLAUDE_CODEX_REVIEW_EFFORT:-high}" \
    - 2>/dev/null | tee -a "$LIVE_LOG" > "$RUN_LOG"
RC=${PIPESTATUS[1]}                              # codex's exit through the pipe, NOT tee's

REVIEW=$(codex_jsonl_final_message "$RUN_LOG")   # per-run private JSONL fallback
[[ -s "$OUT_FILE" ]] && REVIEW=$(cat "$OUT_FILE")   # prefer codex's clean final message

for _f in "$RUN_LOG" "$OUT_FILE"; do [[ "$_f" != /dev/null ]] && rm -f "$_f" 2>/dev/null; done

# 7. Fail CLOSED on infra failure (changed 2026-07-25; it used to fail open and
#    let the turn end with an advisory).
#
#    "Never block because codex could not run" is the unavailable-dependency
#    case, and CLAUDE.md is explicit about it: stash the work, release any
#    lease so peers are not blocked by a dead window, file the outage, exit. Do
#    not route around it, do not proceed for now. A turn that ships unreviewed
#    because the reviewer was down is indistinguishable from one the reviewer
#    approved - and that is the defect behind every scar in this campaign.
#
#    Worth knowing before assuming an outage: on 2026-07-25 eight separate
#    "reviewer down" filings (#230/#240/#243/#251/#254/#256, plus #208/#249)
#    were all root-caused by 35112df7 to the CALLER, not the service - either
#    --permission-mode default, which hangs a headless reviewer on a permission
#    prompt and returns nothing, or a 180-300s bound against a review that
#    genuinely needs 148-162s. Every one of those verdicts came back on the
#    first try once the invocation was fixed. Check the invocation before
#    declaring an outage.
if [[ $RC -ne 0 || -z "$REVIEW" ]]; then
    stop_guard_emit "CODEX AUTO-REVIEW COULD NOT RUN (exit ${RC}$([[ -z "$REVIEW" ]] && printf ', empty output')).

This turn has NOT been reviewed, so it is not approvable. The review is not
optional and this block does not time out.

FIRST, suspect the caller, not the service. Eight recorded 'reviewer outages'
in this campaign were caller-side: a too-short timeout, or --permission-mode
default hanging a headless call. The bound here is
CLAUDE_CODEX_REVIEW_TIMEOUT (currently ${CLAUDE_CODEX_REVIEW_TIMEOUT:-600}s); a real review takes 148-162s.
Check: codex --version, and ~/.codex-review.live.log for this run.

If codex is GENUINELY unavailable (quota, outage), that is a dependency
failure to report, not to work around:
  1. Stash the work.
  2. Release any library-edit lease, so peers are not blocked by a dead window:
       tools\\Invoke-LibraryEditLease.ps1 -Action Release -Owner <your-marker>
  3. File it: gh issue create -R potatoqualitee/migration --label needs-operator
  4. Stop. Do not keep working with the reviewer down."
    exit 0
fi

# 8. Parse the verdict from the FINAL non-empty line only — a "VERDICT: CLEAN"
#    buried mid-review (e.g. quoted in a finding) must not flip the result.
#    Anything else fails closed (blocks).
LAST_LINE=$(printf '%s\n' "$REVIEW" | grep -vE '^[[:space:]]*$' | tail -1)
if [[ "$LAST_LINE" =~ ^VERDICT:[[:space:]]*CLEAN[[:space:]]*$ ]]; then
    VERDICT="CLEAN"
elif [[ "$LAST_LINE" =~ ^VERDICT:[[:space:]]*CHANGES_REQUESTED[[:space:]]*$ ]]; then
    VERDICT="CHANGES_REQUESTED"
else
    VERDICT=""    # missing/garbled final line -> treated as CHANGES_REQUESTED below
fi

# A CLEAN verdict on a truncated diff is not trustworthy.
if [[ "$VERDICT" == "CLEAN" && -n "$TRUNCATED" ]]; then
    VERDICT="CHANGES_REQUESTED"
    REVIEW="$REVIEW"$'\n\n(Auto-review note: the diff exceeded the review size limit and was truncated; split the change set or set CLAUDE_CODEX_REVIEW_MAXBYTES higher to review it whole.)'
fi

# Charge the automatic round only on paths that BLOCK. An approved turn is not
# one of those, and charging it would make every later turn in a healthy session
# start with a marker touch.
#
# Verified, not hoped: an unwritable marker is the budget silently ceasing to
# exist, so it is said out loud in the block rather than assumed. These paths
# block either way, so the finding is never lost to this.
AUTOSPENT_WARN=""
mark_autospent() {
    [[ -n "${AUTOSPENT_FILE:-}" ]] || return 0
    printf '%s' "$PAYLOAD_HASH" > "$AUTOSPENT_FILE" 2>/dev/null
    # Read it back. -s alone is not the check: a directory is non-empty by that
    # test, so a path that swallowed the redirect would report itself written.
    [[ -f "$AUTOSPENT_FILE" && "$(cat "$AUTOSPENT_FILE" 2>/dev/null)" == "$PAYLOAD_HASH" ]] && return 0
    AUTOSPENT_WARN=$'\n\n(CODEX AUTO-REVIEW CANNOT BOUND ITS ROUNDS: the automatic-round marker '"$AUTOSPENT_FILE"$' could not be written, so this round was not recorded and the next turn will spend another full review. Check that directory -- missing, not yours, or full.)'
    return 0
}

if [[ "$VERDICT" == "CLEAN" ]]; then
    # TOCTOU guard, fail CLOSED: the minutes-long review run is a window in
    # which the bytes on disk can change. A CLEAN verdict stands only if the
    # payload re-measures cleanly and hashes identically - an approval that
    # merely skipped the cache still shipped code the reviewer never saw.
    build_session_payload
    if [[ -n "$MEASURE_FAIL" ]]; then
        mark_autospent
        stop_guard_emit "CODEX AUTO-REVIEW COULD NOT CONFIRM ITS VERDICT: the reviewed files failed to re-measure after the review ran, so the CLEAN cannot be tied to what is on disk:

$MEASURE_FAIL
Fix the measurement and end the turn again.$AUTOSPENT_WARN"
        exit 0
    fi
    if [[ "$(payload_scope_hash)" != "$PAYLOAD_HASH" ]]; then
        mark_autospent
        stop_guard_emit "CODEX AUTO-REVIEW: this session's changes or review scope shifted while the reviewer was running, so its CLEAN verdict no longer describes what is on disk. End the turn again to review the current state.$AUTOSPENT_WARN"
        exit 0
    fi
    [[ -n "$CLEAN_FILE" ]] && printf '%s' "$PAYLOAD_HASH" > "$CLEAN_FILE" 2>/dev/null
    # A clean verdict must not swallow the scope warnings: files in foreign
    # repos were still not reviewed, and silence here is how scope loss hides.
    [[ -n "$DROPPED_NOTE" ]] && emit_system_message "$DROPPED_NOTE"
    [[ -n "$LEGACY_NOTE" ]] && emit_system_message "$LEGACY_NOTE"
    codex_memory_clear_prev
    stop_guard_emit ""    # approved -> reset streak, allow
    exit 0
fi

# 9. CHANGES_REQUESTED, or a missing/garbled verdict -> block (fail safe).
#    Save the findings so the NEXT round's reviewer verifies fixes against
#    them instead of re-reviewing blind, and teach the dispute protocol so a
#    false positive gets a durable ruling instead of an argument loop.
codex_memory_save_prev "$REVIEW"
DISPUTE_HOWTO='If a finding is a FALSE POSITIVE (it contradicts CLAUDE.md or a documented project ruling), do not ignore it and do not burn rounds arguing: append ONE JSON line to .claude/codex-review-dispositions.jsonl -- {"date":"YYYY-MM-DD","file":"<repo-relative path>","finding":"<short summary of the finding>","ruling":"rejected","reason":"<why it is wrong, citing the governing rule>"} -- then fix everything else. The ledger edit is itself reviewed next round (an illegitimate ruling is a finding), and legitimate rulings suppress materially-matching findings from then on.'
[[ -n "$DROPPED_NOTE" ]] && REVIEW="$REVIEW"$'\n\n'"($DROPPED_NOTE)"
REASON=$(printf 'CODEX AUTO-REVIEW -- address these before finishing this turn:\n\n%s\n\n%s\n\n(Reviewer: %s, effort %s. There is no session opt-out: fix the findings, or record a disposition in the ledger if one is wrong.)' \
    "$REVIEW" "$DISPUTE_HOWTO" "${CLAUDE_CODEX_REVIEW_MODEL:-gpt-5.6-sol}" "${CLAUDE_CODEX_REVIEW_EFFORT:-high}")
mark_autospent
stop_guard_emit "$REASON$AUTOSPENT_WARN"
exit 0

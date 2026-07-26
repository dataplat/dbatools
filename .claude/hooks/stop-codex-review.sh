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

# Extensions worth reviewing, PLUS markdown — docs are deliverables, reviewed
# for accuracy rather than code style.
CODE_EXT_RE='\.(ps1|psm1|psd1|cs|sql|js|ts|html|go|py|sh|md)$'

SESSION_ID=$(hook_field '.session_id')

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

# Defer entirely if another git process holds any campaign index lock.
for _r in "${CAMPAIGN_ROOTS[@]}"; do
    [[ -f "$_r/.git/index.lock" ]] && exit 0
done

# 2. Scope to THIS session's writes only.
SESSION_STATE="$HOOK_STATE_ROOT/session-files/${SESSION_ID}.txt"
if [[ -z "$SESSION_ID" || ! -f "$SESSION_STATE" ]]; then
    stop_guard_emit ""    # nothing tracked for this session -> nothing to review
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

# Build CODE_FILES + PAYLOAD from the session's code files. Re-callable: the
# CLEAN path calls it again to confirm nothing changed during the
# (minutes-long) codex run before caching the approval (TOCTOU guard).
build_session_payload() {
    CODE_FILES=""
    PAYLOAD=""
    DROPPED=0
    local f rf spec d root file_root rel
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        # Canonicalize before the containment check: a traversal path must not
        # be read into the prompt. -m resolves ".." without requiring the file
        # to exist (deleted files must still resolve).
        rf=$(realpath -m "$(hook_to_unix_path "$f")" 2>/dev/null) || continue
        [[ -n "$rf" ]] || continue
        # Resolve the file to ITS OWN campaign repo (most-specific root wins).
        # A file outside every campaign root is counted, never silently lost:
        # silent scope loss is exactly how this gate died the first time.
        file_root=""
        for root in "${CAMPAIGN_ROOTS[@]}"; do
            if [[ "$rf" == "$root/"* ]]; then file_root="$root"; break; fi
        done
        if [[ -z "$file_root" ]]; then DROPPED=$((DROPPED+1)); continue; fi
        rel="${rf#$file_root/}"
        # Literal, repo-relative pathspec: git pathspecs glob by default, so a
        # file named e.g. `*.ps1` could otherwise pull unrelated files in.
        spec=":(literal)${rel}"
        # diff vs HEAD first: catches modifications AND deletions of tracked
        # files. For an untracked, still-present file that yields nothing
        # here, fall back to --no-index so its full content is reviewed.
        d=$(git -C "$file_root" diff --no-color HEAD -- "$spec" 2>/dev/null)
        if [[ -z "$d" && -f "$rf" ]] && ! git -C "$file_root" ls-files --error-unmatch -- "$spec" >/dev/null 2>&1; then
            d=$(cd "$file_root" && git diff --no-index --no-color -- /dev/null "$rel" 2>/dev/null)
        fi
        [[ -z "$d" ]] && continue                        # written but no net change
        CODE_FILES+="${rf#/mnt/c/github/}"$'\n'
        PAYLOAD+="$d"$'\n'
    done <<< "$SESSION_FILES"
}

# 3. Build the changed-file list + a bounded diff payload.
build_session_payload
DROPPED_NOTE=""
if (( DROPPED > 0 )); then
    DROPPED_NOTE="codex auto-review: ${DROPPED} tracked file(s) fell outside the campaign roots and were NOT reviewed."
fi
if [[ -z "$PAYLOAD" ]]; then
    [[ -n "$DROPPED_NOTE" ]] && emit_system_message "$DROPPED_NOTE"
    codex_memory_clear_prev
    stop_guard_emit ""
    exit 0
fi

# Convergence hash is taken from the FULL diff, BEFORE any truncation, and
# uses sha256: this hash authorizes the CLEAN cache and per-diff budget.
PAYLOAD_HASH=$(printf '%s' "$PAYLOAD" | sha256sum | cut -d' ' -f1)

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

    # Already approved this exact diff? Don't re-spend a codex call or re-block.
    if [[ -f "$CLEAN_FILE" && "$(cat "$CLEAN_FILE" 2>/dev/null)" == "$PAYLOAD_HASH" ]]; then
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
codex_review_setup_livelog

OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-review-out.XXXXXXXX" 2>/dev/null) || OUT_FILE=/dev/null
RUN_LOG=$(mktemp "${TMPDIR:-/tmp}/codex-review.XXXXXXXX" 2>/dev/null) || RUN_LOG=/dev/null

printf '%s' "$PROMPT" | timeout "${CLAUDE_CODEX_REVIEW_TIMEOUT:-600}" codex exec \
    --json \
    -C "$CODEX_CWD" \
    --skip-git-repo-check \
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

if [[ "$VERDICT" == "CLEAN" ]]; then
    codex_memory_clear_prev
    # TOCTOU guard: cache the approval ONLY if the reviewed code is
    # byte-for-byte unchanged since codex approved it — the long review run is
    # a window in which the bytes on disk could have changed.
    build_session_payload
    if [[ "$(printf '%s' "$PAYLOAD" | sha256sum | cut -d' ' -f1)" == "$PAYLOAD_HASH" && -n "$CLEAN_FILE" ]]; then
        printf '%s' "$PAYLOAD_HASH" > "$CLEAN_FILE" 2>/dev/null
    fi
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
stop_guard_emit "$REASON"
exit 0

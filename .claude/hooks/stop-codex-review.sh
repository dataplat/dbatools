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

# 1. Opt-outs: review disabled, or codex not installed (a teammate without
#    codex never sees this gate — that is the intended degradation).
if [[ "${CLAUDE_CODEX_REVIEW:-}" == "off" || "${CLAUDE_CODEX_REVIEW:-}" == "OFF" ]]; then
    exit 0
fi
if ! hook_find_codex >/dev/null; then
    # Distinguish "not installed" (silent — the intended degradation) from
    # "installed but cannot start" (say so, at most once every few hours, so a
    # wrong-platform install doesn't masquerade as a codex outage every turn).
    if command -v codex >/dev/null 2>&1; then
        BROKEN_MARKER="$HOOK_STATE_ROOT/codex-broken.warned"
        if [[ -z "$(find "$BROKEN_MARKER" -mmin -240 2>/dev/null)" ]]; then
            touch "$BROKEN_MARKER" 2>/dev/null
            emit_system_message "codex is on PATH but cannot start on this platform (wrong-platform npm install?) — auto-review is skipped. Diagnose: bash .claude/hooks/hooks-doctor.sh"
        fi
    fi
    exit 0
fi

REPO_ROOT=$(hook_to_unix_path "$(git rev-parse --show-toplevel 2>/dev/null)")
[[ -z "$REPO_ROOT" ]] && exit 0

# Defer entirely if another git process holds the index lock.
[[ -f "$REPO_ROOT/.git/index.lock" ]] && exit 0

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
    local f rf spec d
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        # Canonicalize before the containment check: a traversal path like
        # "$REPO_ROOT/../secret" must not be read into the prompt. -m resolves
        # ".." without requiring the file to exist (deleted files must still
        # resolve). Must land inside the repo.
        rf=$(realpath -m "$(hook_to_unix_path "$f")" 2>/dev/null) || continue
        [[ -n "$rf" && "$rf" == "$REPO_ROOT/"* ]] || continue
        f="$rf"
        # Literal, repo-relative pathspec: git pathspecs glob by default, so a
        # file named e.g. `*.ps1` could otherwise pull unrelated files in.
        spec=":(literal)${f#$REPO_ROOT/}"
        # diff vs HEAD first: catches modifications AND deletions of tracked
        # files. For an untracked, still-present file that yields nothing
        # here, fall back to --no-index so its full content is reviewed.
        d=$(git -C "$REPO_ROOT" diff --no-color HEAD -- "$spec" 2>/dev/null)
        if [[ -z "$d" && -f "$f" ]] && ! git -C "$REPO_ROOT" ls-files --error-unmatch -- "$spec" >/dev/null 2>&1; then
            d=$(git -C "$REPO_ROOT" diff --no-index --no-color -- /dev/null "${f#$REPO_ROOT/}" 2>/dev/null)
        fi
        [[ -z "$d" ]] && continue                        # written but no net change
        CODE_FILES+="${f#$REPO_ROOT/}"$'\n'
        PAYLOAD+="$d"$'\n'
    done <<< "$SESSION_FILES"
}

# 3. Build the changed-file list + a bounded diff payload.
build_session_payload
if [[ -z "$PAYLOAD" ]]; then
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

    # Budget exhausted for THIS diff? Say so loudly and let the turn end.
    if [[ -f "$COUNT_FILE" ]]; then
        n=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
        [[ "$n" =~ ^[0-9]+$ ]] || n=0
        if (( n >= ${STOP_GUARD_MAX_BLOCKS:-3} )); then
            emit_system_message "CODEX AUTO-REVIEW gate bypassed after ${n} blocked rounds -- this is NOT an approval; unresolved findings almost certainly remain. Fix the remaining items now or re-review in a fresh turn; raise STOP_GUARD_MAX_BLOCKS for more rounds, or set CLAUDE_CODEX_REVIEW=off to opt out deliberately."
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
codex_review_setup_livelog

OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-review-out.XXXXXXXX" 2>/dev/null) || OUT_FILE=/dev/null
RUN_LOG=$(mktemp "${TMPDIR:-/tmp}/codex-review.XXXXXXXX" 2>/dev/null) || RUN_LOG=/dev/null

printf '%s' "$PROMPT" | timeout "${CLAUDE_CODEX_REVIEW_TIMEOUT:-600}" codex exec \
    --json \
    -C "$REPO_ROOT" \
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

# 7. Fail OPEN on infra failure — never block because codex could not run.
if [[ $RC -ne 0 || -z "$REVIEW" ]]; then
    emit_system_message "codex auto-review unavailable this turn (codex error or timeout) -- proceeding without it. Set CLAUDE_CODEX_REVIEW=off to silence."
    stop_guard_emit ""
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
REASON=$(printf 'CODEX AUTO-REVIEW -- address these before finishing this turn:\n\n%s\n\n%s\n\n(Reviewer: %s, effort %s. Disable for this session with CLAUDE_CODEX_REVIEW=off.)' \
    "$REVIEW" "$DISPUTE_HOWTO" "${CLAUDE_CODEX_REVIEW_MODEL:-gpt-5.6-sol}" "${CLAUDE_CODEX_REVIEW_EFFORT:-high}")
stop_guard_emit "$REASON"
exit 0

#!/bin/bash
# pretooluse-checker-removal-guard.sh - Bar an agent from weakening a
# verification step instead of fixing it.
#
# WHY THIS EXISTS (operator directive 2026-07-25)
#
#   A broken checker is a BLOCKER, not an obstacle. If codex or the reviewer is
#   unavailable, the correct behavior is to STOP AND SAY SO - not to route
#   around it, not to disable it "temporarily", not to add a bypass flag. A
#   process that keeps running while its verification is gone is worse than one
#   that dies, because the death is the only signal the operator gets.
#
# WHAT CHANGED, AND WHY (2026-07-25, second pass)
#
#   The first version of this guard watched four filenames for one deleted
#   string each. Reading the campaign's actual forensic record changed the
#   design, because the record does not describe deletions at all:
#
#     * git log -S across both code repos finds ZERO instances of --no-verify,
#       chmod -x, sed -i, or a checker script being removed.
#     * The four "reviewer outage" filings of 2026-07-25 were the agent
#       behaving correctly - refusing to proceed without a verdict. 35112df7
#       later proved the reviewer was never down; the calls were passing
#       --permission-mode default and a 180s bound against a review that needs
#       148-162s.
#     * The one confirmed instance of a checker being switched off by editing
#       it is dea2e5ea7 (2026-07-06, "disable hooks for now"), which added
#       `exit 0` at line 2 of thirteen hook scripts.
#
#   So the failure to defend against is not deletion. It is a check that still
#   exists, still runs, still reports - and can no longer fail. Three additions
#   follow from that:
#
#     1. MIN-COUNTS. GateStepTable.ps1 declares core steps by tagging rows
#        Kind = "core", and Assert-GateStepTable only refuses ZERO core rows.
#        Retag eight of nine as "conditional" and every marker survives while
#        PASS quietly comes to mean two-ninths of what it did.
#     2. DISABLE SHAPES. `exit 0` near the top, if ($false), || true, an empty
#        catch - tested only against text an edit ADDS, so pre-existing
#        occurrences never block unrelated work.
#     3. SELF-PROTECTION. This guard, its shared library, and its wiring in
#        settings.json are themselves in the surface. Previously this file was
#        the one thing nothing defended: one edit here disarmed everything.
#
# Fires ONLY on those shapes. Ordinary edits to the same files - including
# ordinary fixes to the gate - pass through untouched. A guard that blocks
# unrelated work costs more than the defect it prevents.
#
# To retire a checker legitimately, the operator does it by hand. There is
# deliberately no bypass flag: a flag an agent can set is not a guard.

set -uo pipefail

source "$(dirname "$0")/lib-protected-surface.sh"
hook_read_input

# FAIL CLOSED. The previous version exited 0 when jq was missing, which made
# this guard the very thing it exists to prevent: a check that cannot fail.
# If the input cannot be parsed, the guard cannot know what is being edited,
# and "cannot know" is not "permitted". This is loud and instantly fixable, as
# opposed to silent.
if ! hook_detect_parser; then
    emit_deny "The checker-removal guard cannot parse the tool input: no working JSON parser (jq, python3, or node) is on PATH. This guard refuses to fail open - a verification step that cannot run has not passed. Install jq and retry."
    exit 0
fi

TOOL=$(hook_field '.tool_name')
case "$TOOL" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

FILE_PATH=$(hook_field '.tool_input.file_path')
[[ -n "$FILE_PATH" ]] || exit 0

ROLE=$(surface_classify "$FILE_PATH")
# verdict/tracker roles belong to the sibling guard; this one owns code.
case "$ROLE" in
    hook|wiring|gate) ;;
    *) exit 0 ;;
esac

BASE=$(basename "$FILE_PATH")

# ---------------------------------------------------------------- edit pairs
# Edit and MultiEdit both reduce to (old_string, new_string) pairs; Write is
# handled separately because it has no "before" in the payload.
pairs_json() {
    printf '%s' "$HOOK_INPUT" | "$(command -v jq)" -c '
        if .tool_input.edits then .tool_input.edits[] | {o: .old_string, n: .new_string}
        else {o: .tool_input.old_string, n: .tool_input.new_string} end
    ' 2>/dev/null
}

# count_matches <regex> <text> - matching LINES, which is the right unit here:
# every construct these regexes describe occupies its own line.
#
# grep -c PRINTS the count and EXITS 1 when that count is zero, so the obvious
# `grep -c ... || printf 0` emits "0\n0" and the caller's (( )) dies on it. The
# arithmetic error goes to stderr, the hook keeps running, and the comparison
# is skipped - so the min-count check silently passed everything. Capture
# stdout and ignore the exit status instead.
count_matches() {
    local re="$1" text="$2" n
    n=$(printf '%s' "$text" | grep -cE -- "$re" 2>/dev/null)
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    printf '%s' "$n"
}

deny() {
    emit_deny "$1"
    exit 0
}

VIOLATION=""

# ---------------------------------------------------------------- 1. markers
MARKERS=$(surface_markers "$FILE_PATH")

if [[ "$TOOL" == "Write" ]]; then
    NEW_CONTENT=$(hook_field '.tool_input.content')
    if [[ -f "$FILE_PATH" && -n "$MARKERS" ]]; then
        while IFS= read -r m; do
            [[ -n "$m" ]] || continue
            if grep -qF -- "$m" "$FILE_PATH" 2>/dev/null; then
                grep -qF -- "$m" <<<"$NEW_CONTENT" \
                    || VIOLATION="This rewrite of $BASE drops \"$m\", the marker that wires up the check. The file keeps its shape and stops being load-bearing."
            fi
        done <<<"$MARKERS"
    fi
else
    while IFS= read -r pair; do
        [[ -n "$pair" ]] || continue
        OLD=$(printf '%s' "$pair" | "$(command -v jq)" -r '.o // empty')
        NEW=$(printf '%s' "$pair" | "$(command -v jq)" -r '.n // empty')
        while IFS= read -r m; do
            [[ -n "$m" ]] || continue
            if grep -qF -- "$m" <<<"$OLD"; then
                grep -qF -- "$m" <<<"$NEW" \
                    || VIOLATION="This edit to $BASE removes \"$m\", the marker that wires up the check."
            fi
        done <<<"$MARKERS"
    done < <(pairs_json)
fi

[[ -n "$VIOLATION" ]] && deny "BLOCKED: $VIOLATION

Removing a checker is not a fix for a broken checker. If the dependency is
unavailable, STOP AND REPORT IT - file the outage and let the process die.
A pipeline that runs without its verification looks identical to one that
passed, which is how this campaign ended up re-gating 993 rows (#231).

If this removal is genuinely intended, the operator makes it by hand. There is
no agent-settable override, by design."

# ------------------------------------------------------------- 2. min-counts
# The check a marker cannot make: the construct survives but there is less of
# it. See GateStepTable.ps1 and the Kind = "core" tally.
MINCOUNTS=$(surface_mincounts "$FILE_PATH")
if [[ -n "$MINCOUNTS" ]]; then
    while IFS=$'\t' read -r re minimum; do
        [[ -n "$re" && -n "$minimum" ]] || continue
        if [[ "$TOOL" == "Write" ]]; then
            have=$(count_matches "$re" "$NEW_CONTENT")
            if (( have < minimum )); then
                VIOLATION="This rewrite of $BASE leaves $have occurrence(s) of /$re/, below the required $minimum."
            fi
        else
            while IFS= read -r pair; do
                [[ -n "$pair" ]] || continue
                OLD=$(printf '%s' "$pair" | "$(command -v jq)" -r '.o // empty')
                NEW=$(printf '%s' "$pair" | "$(command -v jq)" -r '.n // empty')
                before=$(count_matches "$re" "$OLD")
                after=$(count_matches "$re" "$NEW")
                if (( after < before )); then
                    VIOLATION="This edit to $BASE reduces /$re/ from $before to $after occurrence(s). The construct survives, but there is less of it - which is how a gate keeps reporting PASS over fewer checks."
                fi
            done < <(pairs_json)
        fi
    done <<<"$MINCOUNTS"
fi

[[ -n "$VIOLATION" ]] && deny "BLOCKED: $VIOLATION

In GateStepTable.ps1 the nine core steps are exactly the rows tagged
Kind = \"core\" (build, importPs7, importPs51, surfaceDiffPs7, surfaceDiffPs51,
integrationPs7, integrationPs51, unitPs7, unitPs51 - unitPs7/unitPs51 were
promoted on 2026-07-24, be91f349). Assert-GateStepTable only refuses ZERO core
rows, so shrinking the set is invisible to it and to every marker check.

Narrowing what PASS means is a checker removal wearing a smaller hat. If the
step genuinely no longer belongs, the operator retires it by hand."

# --------------------------------------------------------- 3. disable shapes
# Tested only against ADDED text, so pre-existing occurrences never block
# unrelated work on the same file.
check_added_text() {
    local added="$1" shape
    [[ -n "$added" ]] || return 0
    while IFS= read -r shape; do
        [[ -n "$shape" ]] || continue
        if grep -qE -- "$shape" <<<"$added"; then
            VIOLATION="This edit adds /$shape/ to $BASE - a shape that makes the check unable to fail."
            return 0
        fi
    done < <(surface_disable_shapes)
}

if [[ "$TOOL" == "Write" ]]; then
    # No "before" to diff against, so use the positional rule: an
    # unconditional `exit 0` up top is the dea2e5ea7 shape.
    if [[ "$BASE" == *.sh ]] && surface_is_early_exit "$NEW_CONTENT"; then
        VIOLATION="This rewrite of $BASE puts an unconditional \`exit 0\` in its opening lines - the exact shape of dea2e5ea7 (\"disable hooks for now\"), which switched off thirteen hook scripts rather than fixing the errors underneath."
    fi
else
    while IFS= read -r pair; do
        [[ -n "$pair" ]] || continue
        OLD=$(printf '%s' "$pair" | "$(command -v jq)" -r '.o // empty')
        NEW=$(printf '%s' "$pair" | "$(command -v jq)" -r '.n // empty')
        # Lines present in new and absent from old = what this edit adds.
        ADDED=$(comm -13 <(sort -u <<<"$OLD") <(sort -u <<<"$NEW") 2>/dev/null)
        check_added_text "$ADDED"
        [[ -n "$VIOLATION" ]] && break
    done < <(pairs_json)
fi

[[ -n "$VIOLATION" ]] && deny "BLOCKED: $VIOLATION

The campaign's whole scar list is this one defect: #74 all-skipped legs gating
green, #208/#249 checkers that printed FAIL and exited 0, four vacuous legs in
#75, the 993 rows of #231. In every one, a check that could not fail was
indistinguishable from a check that passed.

Fix the underlying failure. If it cannot be fixed right now, stash the work,
release any lease, file the outage, and exit non-zero - loudly."

exit 0

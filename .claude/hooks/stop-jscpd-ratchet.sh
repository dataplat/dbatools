#!/bin/bash
# stop-jscpd-ratchet.sh - Block NEW copy-paste duplication at turn end.
#
# One jscpd scan per turn (not per write — the dbatools tree is too large for
# that), comparing the clones that touch this session's written files against
# .jscpd-baseline.json. The turn is blocked when the session introduced
# duplication the baseline does not account for — a brand-new clone
# fingerprint, an existing fingerprint spreading to a NEW file, or an
# existing fingerprint gaining MORE copies.
#
# Fail-OPEN by design: the ratchet blocks ONLY on a positively-detected new
# clone. A missing baseline (the opt-in switch — run jscpd-baseline.sh to
# create it), an unavailable jscpd or Python, a timeout, or a parse error all
# pass quietly — infrastructure trouble must never wedge a turn. Bounded by
# the stop-guard budget like every blocking gate.
set -uo pipefail

source "$(dirname "$0")/lib-stop-guard.sh"
source "$(dirname "$0")/lib-jscpd.sh"

REPO_ROOT=$(hook_to_unix_path "$(git rev-parse --show-toplevel 2>/dev/null)")
[[ -z "$REPO_ROOT" ]] && exit 0

BASELINE="${JSCPD_BASELINE:-$REPO_ROOT/.jscpd-baseline.json}"
[[ -f "$BASELINE" ]] || exit 0    # no baseline -> ratchet not opted in

SESSION_ID=$(hook_field '.session_id')
SESSION_STATE="$HOOK_STATE_ROOT/session-files/${SESSION_ID}.txt"
[[ -z "$SESSION_ID" || ! -f "$SESSION_STATE" ]] && exit 0

# Only the languages the scan tokenizes; skip generated/ignored trees.
TOUCHING=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
        *.ps1|*.psm1|*.sql|*.cs) ;;
        *) continue ;;
    esac
    case "$f" in
        *node_modules*|*/bin/*|*/obj/*|*/tests/*|*allcommands.ps1|*dbatools.psm1) continue ;;
    esac
    TOUCHING+=(--touching "$(jscpd_native_path "$(hook_to_unix_path "$f")")")
done < <(sort -u "$SESSION_STATE")

if [[ ${#TOUCHING[@]} -eq 0 ]]; then
    stop_guard_emit ""
    exit 0
fi

PYTHON=$(jscpd_find_python) || exit 0
jscpd_locate >/dev/null || exit 0

# Scan with the exact settings the baseline was built with — clone detection
# is sensitive to min-tokens and root, and the baseline is the source of truth.
SETTINGS=$($PYTHON "$(jscpd_native_path "$JSCPD_HELPER")" --settings "$(jscpd_native_path "$BASELINE")" 2>/dev/null) || exit 0
SCAN_ROOT=$(printf '%s' "$SETTINGS" | cut -f1)
MIN_TOKENS=$(printf '%s' "$SETTINGS" | cut -f2)
[[ -z "$SCAN_ROOT" || -z "$MIN_TOKENS" ]] && exit 0

SCAN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/jscpd-ratchet.XXXXXXXX") || exit 0
trap 'rm -rf "$SCAN_DIR"' EXIT

if ! ( cd "$REPO_ROOT" && jscpd_scan "$SCAN_ROOT" "$MIN_TOKENS" "$SCAN_DIR" ); then
    exit 0    # scan trouble -> fail open
fi

VERDICT=$( cd "$REPO_ROOT" && $PYTHON "$(jscpd_native_path "$JSCPD_HELPER")" \
    --report "$(jscpd_native_path "$SCAN_DIR/jscpd-report.json")" \
    --root "$SCAN_ROOT" \
    --compare "$(jscpd_native_path "$BASELINE")" \
    "${TOUCHING[@]}" 2>/dev/null )

STATE="${VERDICT%%|*}"
DETAIL="${VERDICT#*|}"

if [[ "$STATE" != "BLOCK" ]]; then
    stop_guard_emit ""
    exit 0
fi

stop_guard_emit "JSCPD RATCHET: this session introduced ${DETAIL} new duplicated code block(s).

New copy-paste duplication is not allowed (duplication the baseline already records is fine).

Fix: extract the shared logic into a helper/private function instead of copying it.
Inspect locally: jscpd <file> --min-tokens ${MIN_TOKENS} --reporters consoleFull

If this duplication is legitimately unavoidable, refresh the baseline and say so:
  .claude/hooks/jscpd-baseline.sh --force"
exit 0

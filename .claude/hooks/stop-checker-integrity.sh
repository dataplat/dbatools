#!/bin/bash
# stop-checker-integrity.sh - Refuse to end a turn in which the verification
# surface changed without being re-approved.
#
# This is the enforcement end of verify-checker-integrity.sh. The PreToolUse
# guards try to stop a bypass as it is attempted; this one asks, at the only
# moment that matters, whether the surface is still what the operator approved
# - regardless of how it got changed. Edit, rm, sed -i, a python one-liner, a
# git operation: they all end here.
#
# It is deliberately NOT satisfiable by waiting. The block budget in
# lib-stop-guard.sh was removed in the same change that added this file, so
# there is no round count that eventually lets the turn close. If the surface
# drifted, either restore it or re-baseline it deliberately and commit that
# decision. Both are one command; neither is silent.
#
# A SILENT RE-BASELINE IS ALSO REPORTED. Re-running --update makes drift
# disappear, so an uncommitted manifest change is treated as a finding in its
# own right. That does not make the tripwire un-defeatable - nothing on this
# box can be, since the agent runs as the file owner - but it does mean
# defeating it leaves a diff in the working tree with the operator's name on
# the decision.

set -uo pipefail

source "$(dirname "$0")/lib-stop-guard.sh"
# Deliberately no STOP_GUARD_SKIP early-exit: this enforces every turn, not
# once per session. A surface that drifts on turn 40 matters as much as one
# that drifted on turn 1.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
VERIFY="$SCRIPT_DIR/verify-checker-integrity.sh"

if [[ ! -f "$VERIFY" ]]; then
    stop_guard_emit "CHECKER INTEGRITY: verify-checker-integrity.sh is missing from .claude/hooks/.

The tripwire over the verification surface cannot run, so nothing currently
confirms that the gate, the hooks, and their wiring are what the operator
approved. A checker that cannot run has not passed.

Restore it (git checkout -- .claude/hooks/verify-checker-integrity.sh) or, if
it was retired deliberately, the operator removes this Stop hook by hand."
    exit 0
fi

REPORT=$(bash "$VERIFY" 2>&1)
STATUS=$?

# Uncommitted manifest edits: drift that was made to disappear rather than fixed.
MANIFEST_DIRTY=""
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if ! git -C "$REPO_ROOT" diff --quiet -- .claude/hooks/checker-manifest.sha256 2>/dev/null; then
        MANIFEST_DIRTY="yes"
    fi
fi

if (( STATUS == 0 )) && [[ -z "$MANIFEST_DIRTY" ]]; then
    stop_guard_emit ""
    exit 0
fi

if (( STATUS == 2 )); then
    stop_guard_emit "CHECKER INTEGRITY: the tripwire could not run.

$REPORT

This is reported as a violation rather than passed over, because a tripwire
that cannot run is indistinguishable from one that found nothing - which is
the exact defect this campaign keeps re-learning (#74, #208/#249, #75, #231)."
    exit 0
fi

DETAIL=""
if (( STATUS != 0 )); then
    DETAIL="$REPORT

"
fi

if [[ -n "$MANIFEST_DIRTY" ]]; then
    DETAIL+="The manifest itself has uncommitted changes. Re-baselining is how drift is
legitimately accepted, so it is not blocked - but it is recorded, because
re-running --update is also how drift is made to disappear without being
fixed. Commit the manifest with a message saying what changed and why.

"
fi

stop_guard_emit "CHECKER INTEGRITY: the verification surface no longer matches the approved baseline.

${DETAIL}Resolve it one of two ways, both deliberate:

  * If this change was NOT intended - restore the file:
      git -C \"$REPO_ROOT\" checkout -- <path>

  * If you changed a checker on purpose - re-baseline AND commit, so the
    decision is on the record rather than in a temp file:
      bash .claude/hooks/verify-checker-integrity.sh --update
      git commit -m \"...\" -- .claude/hooks/checker-manifest.sha256 <path>

MISSING is the case to read hardest: a checker that is gone cannot report that
it is gone. That is why this hook enumerates the manifest rather than scanning
the directory - a scan of what exists can never notice what does not."
exit 0

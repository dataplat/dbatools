#!/bin/bash
# pretooluse-bash-tamper-guard.sh - Close the shell-shaped routes around the
# verification surface, and the off-switches that were left lying next to it.
#
# HONEST SCOPE NOTE
#
#   The Edit/Write guards are the ones with an evidence base. This one is
#   defense in depth: `git log --all -S` across both code repos finds ZERO
#   instances of a checker being removed by rm, mv, sed -i, chmod -x,
#   git checkout --, or git commit --no-verify. Not one, ever. The campaign's
#   own threat model agrees - the original removal guard matched only
#   Edit|Write|MultiEdit and deliberately did not touch Bash.
#
#   It exists anyway because the Edit-side guards are now strong enough that
#   the shell is the obvious next path, and because two of its checks are not
#   speculative at all - the env off-switches below are real, present, and
#   documented in the very error messages that advertise them.
#
# THE OFF-SWITCHES, WHICH ARE THE REAL FINDING HERE
#
#   CLAUDE_CODEX_REVIEW=off     turned the Stop-hook review off entirely. The
#                               hook printed this in its own bypass message.
#   STOP_GUARD_MAX_BLOCKS       set to 0, every Stop block becomes advisory.
#   DBATOOLS_GATELOCK_NAME      redirects the machine-wide gate mutex to a
#                               private name, so the run is NOT serialized
#                               against the fleet - the exact corruption class
#                               GateLock.psm1 says produced rows that reached
#                               DONE still carrying defects.
#
#   Per the campaign's own rule, a flag an agent can set is not a guard. The
#   first two are removed at the source as part of this change; this hook stops
#   them being reintroduced from the command line, and stops the third.
#
# Verb-anchored on purpose: reading these files is always fine. `grep -n exit
# .claude/hooks/*.sh`, `cat`, `ls`, `git log` and friends pass untouched. Only
# a destructive verb aimed at a protected path is refused.

set -uo pipefail

source "$(dirname "$0")/lib-protected-surface.sh"
hook_read_input

# This guard reads one string. If it cannot get that string it knows nothing,
# and blocking every Bash call in the repo would be its own outage - unlike the
# Edit guards, whose blast radius is one file. Fail open here, and rely on the
# integrity tripwire (stop-checker-integrity.sh) to catch what slips past.
hook_detect_parser || exit 0

TOOL=$(hook_field '.tool_name')
[[ "$TOOL" == "Bash" ]] || exit 0

CMD=$(hook_field '.tool_input.command')
[[ -n "$CMD" ]] || exit 0

deny() { emit_deny "$1"; exit 0; }

# ------------------------------------------------------- 1. env off-switches
if grep -qE '\bCLAUDE_CODEX_REVIEW[[:space:]]*=[[:space:]]*["'\'']?(off|OFF|0|false)' <<<"$CMD"; then
    deny "BLOCKED: this sets CLAUDE_CODEX_REVIEW=off, which disables the codex Stop-hook review for the session.

That opt-out has been removed from stop-codex-review.sh, because a flag an
agent can set is not a guard. If codex genuinely cannot run - quota, outage,
wrong-platform install - that is a dependency failure to report, not to switch
off: stash the work, release any lease, file the outage, exit non-zero."
fi

if grep -qE '\bSTOP_GUARD_MAX_BLOCKS[[:space:]]*=' <<<"$CMD"; then
    deny "BLOCKED: this sets STOP_GUARD_MAX_BLOCKS, which controlled how many times a Stop-hook checker could block before it downgraded itself to an advisory and let the turn end.

That budget has been removed. A checker that cannot be satisfied is an operator
event, not a countdown - the old behavior printed \"GATE BYPASSED\" and closed
the turn anyway, which is a check that could not fail."
fi

if grep -qE '\bDBATOOLS_GATELOCK_NAME[[:space:]]*=' <<<"$CMD"; then
    deny "BLOCKED: this sets DBATOOLS_GATELOCK_NAME, which redirects the machine-wide gate mutex to a private name. The run would then NOT be serialized against the rest of the fleet.

GateLock.psm1 exists because concurrent gates and flips pick up half-applied
build state, and its own docstring records that this is how several rows
reached DONE while still carrying defects. If a lock is genuinely stuck, clear
it deliberately - do not run outside it."
fi

# ------------------------------------------------ 2. commit-hook suppression
if grep -qE '\bgit\b[^|;&]*\bcommit\b[^|;&]*(--no-verify|[[:space:]]-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$))' <<<"$CMD"; then
    deny "BLOCKED: this commits with --no-verify (or -n), skipping the pre-commit and commit-msg hooks.

Those hooks are checkers. Skipping them makes the commit look identical to one
that passed them. If a hook is wrong, fix the hook."
fi

# --------------------------------------------------- 3. tampering with files
# A path fragment is protected if surface_classify recognizes it. Rather than
# parse shell, extract path-ish tokens from the command and classify each.
PROTECTED_HIT=""
PROTECTED_ROLE=""
while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    role=$(surface_classify "$tok")
    if [[ -n "$role" ]]; then
        PROTECTED_HIT="$tok"
        PROTECTED_ROLE="$role"
        break
    fi
done < <(grep -oE '[A-Za-z0-9_./\\:-]*(\.claude/(hooks|settings)|tools/|logs/verdicts|trackers/)[A-Za-z0-9_./\\*-]*' <<<"$CMD")

[[ -n "$PROTECTED_HIT" ]] || exit 0

# Destructive verbs, each anchored so a mention inside a read-only command
# (grep/cat/ls/git log) does not trip it.
DESTRUCTIVE=""
grep -qE '(^|[|;&[:space:]])rm([[:space:]]+-[a-zA-Z]+)*[[:space:]]' <<<"$CMD"        && DESTRUCTIVE="rm"
grep -qE '(^|[|;&[:space:]])(unlink|shred|truncate)[[:space:]]'      <<<"$CMD"        && DESTRUCTIVE="unlink/shred/truncate"
grep -qE '(^|[|;&[:space:]])mv[[:space:]]'                           <<<"$CMD"        && DESTRUCTIVE="mv"
grep -qE '(^|[|;&[:space:]])chmod[[:space:]]'                        <<<"$CMD"        && DESTRUCTIVE="chmod"
grep -qE '(^|[|;&[:space:]])sed[[:space:]]+[^|;&]*-i'                <<<"$CMD"        && DESTRUCTIVE="sed -i"
grep -qE '\bgit[[:space:]]+(checkout|restore|rm|clean)\b'            <<<"$CMD"        && DESTRUCTIVE="git checkout/restore/rm/clean"
grep -qE '(^|[^>])>[[:space:]]*[A-Za-z0-9_./\\:-]*(\.claude|tools/|logs/verdicts|trackers/)' <<<"$CMD" && DESTRUCTIVE="output redirection"
grep -qE '(^|[|;&[:space:]])(cp|dd|install)[[:space:]]'              <<<"$CMD"        && DESTRUCTIVE="cp/dd/install"

[[ -n "$DESTRUCTIVE" ]] || exit 0

case "$PROTECTED_ROLE" in
    verdict)
        deny "BLOCKED: this uses $DESTRUCTIVE against a gate verdict artifact ($PROTECTED_HIT).

Verdicts are written by Write-GateJson in tools/Test-MigratedCommand.ps1 and by
nothing else. Creating, moving or removing one by hand fabricates or destroys
the evidence every downstream check trusts - Test-GateVerdictReady validates
only the filename pattern and the recorded statuses, never provenance."
        ;;
    tracker)
        deny "BLOCKED: this uses $DESTRUCTIVE against the tracker inventory ($PROTECTED_HIT).

Tracker rows are the campaign's record of what is claimed done. Edit them with
the Edit tool, one row at a time, so the DONE-flip check can see the
transition - a bulk shell rewrite goes around it."
        ;;
    *)
        deny "BLOCKED: this uses $DESTRUCTIVE against a protected verification file ($PROTECTED_HIT).

A broken checker is a blocker, not an obstacle. Removing, moving, truncating or
reverting one makes the red go away and takes the coverage with it - and the
loss is invisible afterwards, because the thing that would have reported it is
the thing that was removed.

Reading these files is always allowed. If this file genuinely needs to change,
edit it with the Edit tool so the content guards can see what is changing. If a
checker must be retired, the operator does it by hand."
        ;;
esac

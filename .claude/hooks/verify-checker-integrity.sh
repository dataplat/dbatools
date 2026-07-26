#!/bin/bash
# verify-checker-integrity.sh - Tripwire over the verification surface.
#
# WHY A TRIPWIRE AND NOT JUST MORE GUARDS
#
#   Every PreToolUse guard reasons about INTENT: it reads a proposed edit or a
#   command string and decides whether that shape is a bypass. Intent guards
#   are defeatable by an author who picks a shape the pattern does not cover,
#   and on this box the agent has full shell access as the same user that owns
#   the files - the repo is a 9p mount of C:\github\dbatools where every file
#   reports 0777, chattr is unsupported, and sudo needs a password. There is no
#   Linux-side permission that stops a determined write.
#
#   So this checks the RESULT instead. It does not care whether a file changed
#   via Edit, rm, sed -i, a python script, or a git operation. It only asks:
#   does the surface still hash to what the operator last approved?
#
#   That converts "an agent can defeat the guards" into "an agent cannot defeat
#   the guards WITHOUT LEAVING A RECORD", which is the honest ceiling here and
#   is the property the campaign actually needs. Every scar on the list - #74,
#   #208/#249, #75, #231 - is a coverage loss that nobody noticed at the time.
#   Detection is the thing that was missing, not prevention.
#
# MISSING is reported as loudly as DRIFT, and separately: a deleted checker is
# the case where nothing else can report, because the reporter is gone.
#
# Exit codes:
#   0  surface matches the manifest
#   1  drift, missing files, or unlisted new hooks
#   2  the check itself could not run (no manifest, no sha256 tool) - FAIL
#      CLOSED, because a tripwire that cannot run has not reported "clean"

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
MANIFEST="$SCRIPT_DIR/checker-manifest.sha256"

sha_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
    else
        return 1
    fi
}

if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    echo "CANNOT-RUN no sha256 tool (sha256sum or shasum) on PATH" >&2
    exit 2
fi

# The surface, as repo-relative paths. Kept here rather than in
# lib-protected-surface.sh because that file answers "is this path protected?"
# for a single path, while this one has to ENUMERATE - and enumeration is what
# catches a deletion.
#
# LAYOUT ASSUMPTION, STATED OUT LOUD: the campaign repos keep their real
# checkers FLAT in .claude/hooks/. -maxdepth 1 is therefore correct here and
# the assertions below exist to catch the day it stops being. A repo that nests
# hooks in .claude/hooks/<bucket>/ needs the recursive form instead - see
# dbatools.pro.new, where a flat glob matches zero files and would have printed
# "OK 0 files match" over 161 unprotected hooks.
surface_paths() {
    (
        cd "$REPO_ROOT" || exit 0
        find .claude/hooks -maxdepth 1 -type f -name '*.sh' 2>/dev/null
        [[ -f .claude/settings.json ]] && echo .claude/settings.json
        for f in tools/GateStepTable.ps1 \
                 tools/Test-MigratedCommand.ps1 \
                 tools/Invoke-GateWithWorkstationSteps.ps1 \
                 tools/Invoke-GateLocked.ps1 \
                 tools/GateLock.psm1 \
                 tools/Switch-CommandExport.ps1 \
                 tools/claude-bash-guard.sh; do
            [[ -f "$f" ]] && echo "$f"
        done
    ) | sort -u
}

# ------------------------------------------------------------------- update
if [[ "${1:-}" == "--update" ]]; then
    # Never baseline an empty surface. A manifest with no entries verifies
    # clean forever, over anything - the same shape as #75's vacuous legs, and
    # the one this file is least able to notice on its own afterwards, because
    # from then on it has nothing to compare and nothing to report.
    # grep -c prints 0 and EXITS 1 when there are no matches, so the count is
    # read defensively rather than through a short-circuit that would swallow it.
    count=$(surface_paths | grep -c .)
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    if (( count == 0 )); then
        echo "REFUSING to baseline an EMPTY surface - found 0 checker files." >&2
        echo "  A manifest with no entries verifies clean forever. Check the" >&2
        echo "  layout assumption in surface_paths() before re-running." >&2
        exit 2
    fi
    {
        echo "# checker-manifest.sha256 - the verification surface as last approved."
        echo "#"
        echo "# Regenerate with: bash .claude/hooks/verify-checker-integrity.sh --update"
        echo "# Then COMMIT IT. An uncommitted manifest change is itself reported by"
        echo "# stop-checker-integrity.sh, so silently re-baselining a weakened checker"
        echo "# does not go unrecorded - which is the whole point of the file."
        echo "#"
        echo "# Generated from HEAD $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
        while IFS= read -r rel; do
            [[ -n "$rel" ]] || continue
            printf '%s  %s\n' "$(sha_of "$REPO_ROOT/$rel")" "$rel"
        done < <(surface_paths)
    } > "$MANIFEST"
    echo "Wrote $(grep -cv '^#' "$MANIFEST") entries to ${MANIFEST#"$REPO_ROOT"/}"
    exit 0
fi

# ------------------------------------------------------------------- verify
if [[ ! -f "$MANIFEST" ]]; then
    echo "CANNOT-RUN manifest missing: ${MANIFEST#"$REPO_ROOT"/}" >&2
    echo "  A tripwire with no baseline has not reported clean - it has not run." >&2
    echo "  Create it deliberately: bash .claude/hooks/verify-checker-integrity.sh --update" >&2
    exit 2
fi

# The same assertion from the verify side: an empty manifest that already
# exists on disk would pass every file that ever existed. CANNOT-RUN, not clean.
if (( $(grep -cv '^#' "$MANIFEST") == 0 )); then
    echo "CANNOT-RUN manifest lists 0 files - it would verify clean over anything" >&2
    exit 2
fi

findings=0
listed=""

while read -r want rel; do
    [[ -n "${want:-}" && -n "${rel:-}" ]] || continue
    [[ "$want" == \#* ]] && continue
    listed+="$rel"$'\n'
    abs="$REPO_ROOT/$rel"
    if [[ ! -f "$abs" ]]; then
        echo "MISSING  $rel"
        echo "         a checker in the manifest is gone from disk"
        findings=$((findings + 1))
        continue
    fi
    got=$(sha_of "$abs")
    if [[ "$got" != "$want" ]]; then
        echo "DRIFT    $rel"
        echo "         expected $want"
        echo "         actual   $got"
        findings=$((findings + 1))
    fi
done < <(grep -v '^#' "$MANIFEST")

# A hook added since the baseline is not automatically wrong, but it is
# unreviewed - and "add a permissive hook alongside the strict one" is a bypass
# shape that drift alone would never show.
while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    grep -qxF "$rel" <<<"$listed" || {
        echo "UNLISTED $rel"
        echo "         present on disk, absent from the manifest"
        findings=$((findings + 1))
    }
done < <(surface_paths)

if (( findings == 0 )); then
    echo "OK $(grep -cv '^#' "$MANIFEST") files match the approved surface"
    exit 0
fi

echo ""
echo "$findings finding(s). If YOU changed a checker deliberately, re-baseline and commit:"
echo "  bash .claude/hooks/verify-checker-integrity.sh --update"
exit 1

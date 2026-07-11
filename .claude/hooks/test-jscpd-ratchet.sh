#!/bin/bash
# test-jscpd-ratchet.sh - Focused tests for the jscpd duplication ratchet engine.
#
#   bash .claude/hooks/test-jscpd-ratchet.sh
#
# Covers the failure modes the hooks must get right:
#   * resolver: an existing-but-broken $JSCPD_BIN must NOT report resolvable
#   * resolver: a POSIX npm -g symlink shim (bin -> lib/node_modules) resolves
#   * publish:  --no-clobber refuses an existing baseline (content untouched)
#   * verdicts: baselined duplication passes, new duplication blocks
#   * attribution: duplication already present in a touched file's pre-write
#     snapshot passes; a copy the session added blocks
#
# Requires node. Tests that need a real jscpd scan skip when none resolves —
# the same fail-open behavior the hooks themselves have.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ENGINE="$SCRIPT_DIR/lib-jscpd.js"
PASS=0; FAIL=0; SKIP=0

t_pass() { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$1"; }
t_fail() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$1"; }
t_skip() { SKIP=$((SKIP + 1)); printf '  [SKIP] %s\n' "$1"; }

NODE_BIN=""
for c in node node.exe; do
    if command -v "$c" >/dev/null 2>&1; then
        # Absolute path on purpose: T2 runs the engine under a minimal PATH
        # containing only the fixture's fake global bin, so a bare "node"
        # would vanish there.
        NODE_BIN=$(command -v "$c")
        break
    fi
done
if [[ -z "$NODE_BIN" ]]; then
    echo "node is required to run these tests" >&2
    exit 1
fi

WORK=$(mktemp -d) || exit 1
trap 'find "$WORK" -depth -delete 2>/dev/null' EXIT

# Replicates the snapshot key derivation shared by pre-write-snapshot-baseline.sh
# (bash) and lib-jscpd.js (node): sha1(canonical path), lowercased only on the
# case-insensitive Windows filesystems.
snap_key() {
    local p
    p=$(realpath -m "$1" 2>/dev/null) || return 1
    p="${p//\\//}"
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*) p=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]') ;;
    esac
    printf '%s' "$p" | sha1sum | cut -d' ' -f1
}

echo "jscpd ratchet engine tests"
echo "=========================="

# ---- T1: broken JSCPD_BIN must not resolve -------------------------------
FALSE_BIN=$(command -v false)
if JSCPD_BIN="$FALSE_BIN" "$NODE_BIN" "$ENGINE" --where >/dev/null 2>&1; then
    t_fail "T1 --where accepts a binary that cannot run (JSCPD_BIN=$FALSE_BIN)"
else
    t_pass "T1 --where rejects an existing-but-broken JSCPD_BIN"
fi

# ---- T2: POSIX npm -g symlink shim resolves to the package ---------------
GBASE="$WORK/global"
mkdir -p "$GBASE/bin" "$GBASE/lib/node_modules/jscpd"
printf '{"bin":{"jscpd":"./fake.js"}}' > "$GBASE/lib/node_modules/jscpd/package.json"
printf 'process.exit(0);\n' > "$GBASE/lib/node_modules/jscpd/fake.js"
if ln -s ../lib/node_modules/jscpd/fake.js "$GBASE/bin/jscpd" 2>/dev/null; then
    WHERE_OUT=$(HOME="$WORK/nohome" USERPROFILE="$WORK/nohome" CLAUDE_PROJECT_DIR="$WORK/noproj" PATH="$GBASE/bin" \
        "$NODE_BIN" "$ENGINE" --where 2>/dev/null)
    if [[ "$WHERE_OUT" == *"fake.js"* ]]; then
        t_pass "T2 symlinked global shim resolves to its package launcher"
    else
        t_fail "T2 symlinked global shim not resolved (got: ${WHERE_OUT:-<empty>})"
    fi
else
    t_skip "T2 filesystem does not support symlinks here"
fi

# ---- fixture for scan-dependent tests -------------------------------------
if ! "$NODE_BIN" "$ENGINE" --where >/dev/null 2>&1; then
    t_skip "T3-T7 no usable jscpd on this machine (bash .claude/hooks/jscpd-baseline.sh installs one)"
    echo
    echo "passed=$PASS failed=$FAIL skipped=$SKIP"
    [[ $FAIL -eq 0 ]] || exit 1
    exit 0
fi

FIX="$WORK/fixture"
mkdir -p "$FIX/src"
# A chunky shared block (well over the 30-token threshold the fixture uses).
BLOCK='function Get-TestThing {
    $config = @{ Name = "alpha"; Size = 42; Owner = "dba"; Region = "west" }
    $result = @()
    foreach ($item in $config.Keys) {
        $value = $config[$item]
        if ($value -is [int]) {
            $result += "$item has numeric value $value"
        } else {
            $result += "$item has string value $value"
        }
    }
    Write-Output ($result -join "; ")
    return $result.Count
}'
printf '%s\n# trailing alpha\n' "$BLOCK" > "$FIX/src/a.ps1"
printf '# leading beta\n%s\n' "$BLOCK" > "$FIX/src/b.ps1"

run_compare() {
    # run_compare <baseline> [extra engine args...] -> stdout verdict
    local baseline="$1"
    shift
    (cd "$FIX" && "$NODE_BIN" "$ENGINE" --compare "$baseline" --touching "$FIX/src/a.ps1" "$@" 2>/dev/null)
}

# ---- T3: --no-clobber refuses an existing baseline ------------------------
printf 'sentinel' > "$FIX/existing.json"
if (cd "$FIX" && "$NODE_BIN" "$ENGINE" --root src --min-tokens 30 --baseline-out existing.json --no-clobber >/dev/null 2>&1); then
    t_fail "T3 --no-clobber overwrote an existing baseline"
else
    if [[ "$(cat "$FIX/existing.json")" == "sentinel" ]]; then
        t_pass "T3 --no-clobber refuses and leaves the existing baseline untouched"
    else
        t_fail "T3 --no-clobber failed but the baseline content changed"
    fi
fi

# ---- T4: baselined duplication passes -------------------------------------
if (cd "$FIX" && "$NODE_BIN" "$ENGINE" --root src --min-tokens 30 --baseline-out base.json >/dev/null 2>&1) \
    && [[ -s "$FIX/base.json" ]]; then
    VERDICT=$(run_compare base.json)
    if [[ "$VERDICT" == OK\|* ]]; then
        t_pass "T4 duplication recorded in the baseline does not block"
    else
        t_fail "T4 expected OK| for baselined duplication, got: ${VERDICT:-<empty>}"
    fi
else
    t_fail "T4 baseline generation failed on the fixture"
fi

# ---- T5: un-baselined duplication blocks (no snapshots) -------------------
printf '{"generatedFrom":"src","minTokens":30,"fingerprintVersion":3,"clones":{}}\n' > "$FIX/empty.json"
VERDICT=$(run_compare empty.json)
if [[ "$VERDICT" == BLOCK\|* ]]; then
    t_pass "T5 un-baselined duplication blocks when no snapshots exist"
else
    t_fail "T5 expected BLOCK| with an empty baseline, got: ${VERDICT:-<empty>}"
fi

# ---- T6: pre-existing duplication in a touched file does not block --------
SNAP="$WORK/session.snap"
mkdir -p "$SNAP"
KEY=$(snap_key "$FIX/src/a.ps1")
cp "$FIX/src/a.ps1" "$SNAP/${KEY}.base"    # pre-write content already had the clone
VERDICT=$(run_compare empty.json --snap-dir "$SNAP")
if [[ "$VERDICT" == OK\|* ]]; then
    t_pass "T6 clone already present in the pre-write snapshot does not block"
else
    t_fail "T6 expected OK| when the snapshot already contains the clone, got: ${VERDICT:-<empty>}"
fi

# ---- T7: a copy the session added blocks ----------------------------------
printf '# pristine, no duplicated block yet\n' > "$SNAP/${KEY}.base"
VERDICT=$(run_compare empty.json --snap-dir "$SNAP")
if [[ "$VERDICT" == BLOCK\|* ]]; then
    t_pass "T7 clone absent from the pre-write snapshot blocks (session added it)"
else
    t_fail "T7 expected BLOCK| when the snapshot lacks the clone, got: ${VERDICT:-<empty>}"
fi

# ---- T8: COPYFILE_EXCL fallback (link path force-disabled) -----------------
printf 'sentinel' > "$FIX/fb.json"
if (cd "$FIX" && JSCPD_TEST_NO_LINK=1 "$NODE_BIN" "$ENGINE" --root src --min-tokens 30 --baseline-out fb.json --no-clobber >/dev/null 2>&1); then
    t_fail "T8 copy-fallback --no-clobber overwrote an existing baseline"
elif [[ "$(cat "$FIX/fb.json")" != "sentinel" ]]; then
    t_fail "T8 copy-fallback refused but the baseline content changed"
else
    rm "$FIX/fb.json"
    if (cd "$FIX" && JSCPD_TEST_NO_LINK=1 "$NODE_BIN" "$ENGINE" --root src --min-tokens 30 --baseline-out fb.json --no-clobber >/dev/null 2>&1) \
        && "$NODE_BIN" -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$FIX/fb.json" 2>/dev/null; then
        t_pass "T8 copy-fallback refuses an existing baseline and publishes a fresh one intact"
    else
        t_fail "T8 copy-fallback failed to publish to an absent target"
    fi
fi

# ---- T9: concurrent --no-clobber publishers -> exactly one winner ----------
rm -f "$FIX/race.json" "$WORK"/race.rc.*
for i in 1 2 3 4 5; do
    (
        cd "$FIX" && JSCPD_TEST_NO_LINK=1 "$NODE_BIN" "$ENGINE" --root src --min-tokens 30 --baseline-out race.json --no-clobber >/dev/null 2>&1
        echo $? > "$WORK/race.rc.$i"
    ) &
done
wait
WINNERS=$(cat "$WORK"/race.rc.* 2>/dev/null | grep -c '^0$')
if [[ "$WINNERS" == "1" ]] \
    && "$NODE_BIN" -e 'const b = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); if (!b.generatedFrom || !b.clones) process.exit(1)' "$FIX/race.json" 2>/dev/null; then
    t_pass "T9 five concurrent --no-clobber publishers: one winner, output intact"
else
    t_fail "T9 expected exactly 1 winning publisher and valid output, got winners=$WINNERS"
fi

# ---- T10: mid-line clone touched on the SECOND side still attributes ------
# The shared token run starts and ends MID-LINE (differing text on the same
# lines), so each side's whole-line fragment differs — attribution must use
# the touched side's own fragment, not the first side's.
mkdir -p "$FIX/src2"
MIDBLOCK='$stamp = Get-Date -Format "yyyyMMdd"; $mode = "alpha"
$catalog = @{ Name = "warehouse"; Size = 512; Owner = "dba"; Tier = "gold" }
$entries = @()
foreach ($slot in $catalog.Keys) {
    $current = $catalog[$slot]
    if ($current -is [int]) {
        $entries += "numeric slot $slot holds $current"
    } else {
        $entries += "string slot $slot holds $current"
    }
}
Write-Output ($entries -join " / ")'
printf '$who = "alice"; %s; $done = "a"\n' "$MIDBLOCK" > "$FIX/src2/m1.ps1"
printf '$who = "bartholomew-the-second"; %s; $done = "bbb"\n' "$MIDBLOCK" > "$FIX/src2/m2.ps1"
printf '{"generatedFrom":"src2","minTokens":30,"fingerprintVersion":3,"clones":{}}\n' > "$FIX/empty2.json"
SNAP2="$WORK/session2.snap"
mkdir -p "$SNAP2"
KEY2=$(snap_key "$FIX/src2/m2.ps1")
printf '# pristine second side\n' > "$SNAP2/${KEY2}.base"
VERDICT=$(cd "$FIX" && "$NODE_BIN" "$ENGINE" --compare empty2.json --touching "$FIX/src2/m2.ps1" --snap-dir "$SNAP2" 2>/dev/null)
if [[ "$VERDICT" == BLOCK\|* ]]; then
    t_pass "T10 mid-line clone added on the second side blocks"
else
    t_fail "T10 expected BLOCK| for a mid-line second-side copy, got: ${VERDICT:-<empty>}"
fi
cp "$FIX/src2/m2.ps1" "$SNAP2/${KEY2}.base"
VERDICT=$(cd "$FIX" && "$NODE_BIN" "$ENGINE" --compare empty2.json --touching "$FIX/src2/m2.ps1" --snap-dir "$SNAP2" 2>/dev/null)
if [[ "$VERDICT" == OK\|* ]]; then
    t_pass "T10b mid-line clone pre-existing on the second side passes"
else
    t_fail "T10b expected OK| for a pre-existing mid-line second-side clone, got: ${VERDICT:-<empty>}"
fi

# ---- T11: snapshot key parity between the bash hook and the node engine ----
# Run under Git Bash, this exercises the drive-letter (/c/x vs C:/x) branch.
KEY_BASH=$(snap_key "$FIX/src/a.ps1")
KEY_NODE=$("$NODE_BIN" "$ENGINE" --snap-key "$FIX/src/a.ps1" 2>/dev/null)
if [[ -n "$KEY_BASH" && "$KEY_BASH" == "$KEY_NODE" ]]; then
    t_pass "T11 bash hook and node engine derive the same snapshot key"
else
    t_fail "T11 key mismatch: bash=$KEY_BASH node=$KEY_NODE"
fi

# ---- T12: overhang-only edit does not read as new duplication --------------
# The clone in src2 starts and ends mid-line; editing only the NON-cloned
# prefix on the clone's first line must keep the fingerprint stable, so a
# baseline that records the clone still accounts for it afterwards.
if (cd "$FIX" && "$NODE_BIN" "$ENGINE" --root src2 --min-tokens 30 --baseline-out base2.json >/dev/null 2>&1); then
    sed -i.bak 's/"alice"/"alexandra-edited-overhang"/' "$FIX/src2/m1.ps1" && rm -f "$FIX/src2/m1.ps1.bak"
    VERDICT=$(cd "$FIX" && "$NODE_BIN" "$ENGINE" --compare base2.json --touching "$FIX/src2/m1.ps1" 2>/dev/null)
    if [[ "$VERDICT" == OK\|* ]]; then
        t_pass "T12 editing only the clone's line overhang stays baselined"
    else
        t_fail "T12 expected OK| after an overhang-only edit, got: ${VERDICT:-<empty>}"
    fi
else
    t_fail "T12 baseline generation failed on the src2 fixture"
fi

# ---- T13: a baseline from another fingerprint scheme fails OPEN ------------
# Never false-block off mismatched fingerprints; the doctor tells the user to
# regenerate.
printf '{"generatedFrom":"src","minTokens":30,"clones":{}}\n' > "$FIX/legacy.json"
VERDICT=$(run_compare legacy.json)
if [[ "$VERDICT" == OPEN\|* ]]; then
    t_pass "T13 legacy (unversioned) baseline fails open with a regenerate hint"
else
    t_fail "T13 expected OPEN| for a legacy baseline, got: ${VERDICT:-<empty>}"
fi

# ---- T14: offsetting removal cannot mask a session-added copy --------------
# Baseline records the clone across m1+m2 (1 pair). The session then adds a
# SECOND copy inside m1 and deletes m2 — tree-wide the file set shrinks and
# the pair count stays 1, so aggregate baseline accounting alone would pass
# it. The m1 snapshot (one copy) must outrank that and block.
if (cd "$FIX" && "$NODE_BIN" "$ENGINE" --root src2 --min-tokens 30 --baseline-out base3.json >/dev/null 2>&1); then
    SNAP3="$WORK/session3.snap"
    mkdir -p "$SNAP3"
    KEY3=$(snap_key "$FIX/src2/m1.ps1")
    cp "$FIX/src2/m1.ps1" "$SNAP3/${KEY3}.base"
    printf '%s\n' "$MIDBLOCK" >> "$FIX/src2/m1.ps1"
    rm "$FIX/src2/m2.ps1"
    VERDICT=$(cd "$FIX" && "$NODE_BIN" "$ENGINE" --compare base3.json --touching "$FIX/src2/m1.ps1" --snap-dir "$SNAP3" 2>/dev/null)
    if [[ "$VERDICT" == BLOCK\|* ]]; then
        t_pass "T14 added copy blocks despite an offsetting removal elsewhere"
    else
        t_fail "T14 expected BLOCK| for a snapshot-proven added copy, got: ${VERDICT:-<empty>}"
    fi
else
    t_fail "T14 baseline generation failed on the src2 fixture"
fi

# ---- T15: a broken higher-priority install falls through -------------------
# A repo-local node_modules synced from the other OS exists but cannot run;
# the resolver must probe it, skip it, and use the working home install.
BROKEN="$WORK/brokenproj"
mkdir -p "$BROKEN/node_modules/jscpd"
printf '{"bin":{"jscpd":"./broken.js"}}' > "$BROKEN/node_modules/jscpd/package.json"
printf 'process.exit(1);\n' > "$BROKEN/node_modules/jscpd/broken.js"
HOME2="$WORK/home2"
mkdir -p "$HOME2/.dbatools-jscpd/node_modules/jscpd"
printf '{"bin":{"jscpd":"./fake.js"}}' > "$HOME2/.dbatools-jscpd/node_modules/jscpd/package.json"
printf 'process.exit(0);\n' > "$HOME2/.dbatools-jscpd/node_modules/jscpd/fake.js"
WHERE_OUT=$(HOME="$HOME2" USERPROFILE="$HOME2" CLAUDE_PROJECT_DIR="$BROKEN" PATH="" \
    "$NODE_BIN" "$ENGINE" --where 2>/dev/null)
if [[ "$WHERE_OUT" == *"home2"* && "$WHERE_OUT" == *"fake.js"* ]]; then
    t_pass "T15 broken repo-local install falls through to the working home install"
else
    t_fail "T15 expected the home install to win, got: ${WHERE_OUT:-<empty>}"
fi

# ---- T16: a snapshot gap in one file cannot mask proof in another ----------
# Clone spans x1+x2+x3 in the baseline (3 pairwise pairs). The session adds a
# second copy to x2 and deletes x3, so the tree stays at 3 pairs and within
# the baselined file set. x1 is touched but has NO snapshot (unknown); x2's
# snapshot proves the added copy. Scanning must not stop at x1's gap —
# "added" wins over "unknown".
mkdir -p "$FIX/src3"
for n in x1 x2 x3; do
    printf '# %s header\n%s\n' "$n" "$BLOCK" > "$FIX/src3/$n.ps1"
done
if (cd "$FIX" && "$NODE_BIN" "$ENGINE" --root src3 --min-tokens 30 --baseline-out base4.json >/dev/null 2>&1); then
    SNAP4="$WORK/session4.snap"
    mkdir -p "$SNAP4"
    KEY4=$(snap_key "$FIX/src3/x2.ps1")
    cp "$FIX/src3/x2.ps1" "$SNAP4/${KEY4}.base"
    printf '%s\n' "$BLOCK" >> "$FIX/src3/x2.ps1"
    rm "$FIX/src3/x3.ps1"
    VERDICT=$(cd "$FIX" && "$NODE_BIN" "$ENGINE" --compare base4.json \
        --touching "$FIX/src3/x1.ps1" --touching "$FIX/src3/x2.ps1" --snap-dir "$SNAP4" 2>/dev/null)
    if [[ "$VERDICT" == BLOCK\|* ]]; then
        t_pass "T16 snapshot proof in a later touched file wins over an earlier gap"
    else
        t_fail "T16 expected BLOCK| despite x1's missing snapshot, got: ${VERDICT:-<empty>}"
    fi
else
    t_fail "T16 baseline generation failed on the src3 fixture"
fi

# ---- T17: multi-byte text before a clone does not corrupt fragments --------
# jscpd positions are UTF-8 byte offsets; UTF-16 slicing drifts on every
# non-ASCII character. Both sides must produce the identical fragment with no
# overhang leakage, and an edit to the unicode overhang must stay baselined.
mkdir -p "$FIX/srcU"
printf '$who = "éédité-日本語-🚀🚀"; %s; $done = "a"\n' "$MIDBLOCK" > "$FIX/srcU/u1.ps1"
printf '$who = "plain-ascii-prefix-x"; %s; $done = "bb"\n' "$MIDBLOCK" > "$FIX/srcU/u2.ps1"
FRAG_CHECK=$(cd "$FIX" && "$NODE_BIN" "$ENGINE" --root srcU --min-tokens 30 --touching "$FIX/srcU/u1.ps1" 2>/dev/null | "$NODE_BIN" -e '
const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
const entries = Object.entries(data.clones || {});
if (!entries.length) { process.stdout.write("no-clone"); process.exit(0); }
const rec = entries[0][1];
const f1 = ((rec.frags || {})["srcU/u1.ps1"] || [""])[0];
const f2 = ((rec.frags || {})["srcU/u2.ps1"] || [""])[0];
if (f1 && f1 === f2 && !/[éé日🚀]/.test(f1)) process.stdout.write("clean");
else process.stdout.write("corrupt");
')
if [[ "$FRAG_CHECK" == "clean" ]]; then
    t_pass "T17 unicode overhang: identical fragments on both sides, no leakage"
else
    t_fail "T17 unicode overhang corrupted fragments ($FRAG_CHECK)"
fi
if (cd "$FIX" && "$NODE_BIN" "$ENGINE" --root srcU --min-tokens 30 --baseline-out baseU.json >/dev/null 2>&1); then
    sed -i.bak 's/éédité-日本語-🚀🚀/übermäßig-编辑过-🎯/' "$FIX/srcU/u1.ps1" && rm -f "$FIX/srcU/u1.ps1.bak"
    VERDICT=$(cd "$FIX" && "$NODE_BIN" "$ENGINE" --compare baseU.json --touching "$FIX/srcU/u1.ps1" 2>/dev/null)
    if [[ "$VERDICT" == OK\|* ]]; then
        t_pass "T17b editing a unicode overhang stays baselined"
    else
        t_fail "T17b expected OK| after a unicode overhang edit, got: ${VERDICT:-<empty>}"
    fi
else
    t_fail "T17b baseline generation failed on the srcU fixture"
fi

echo
echo "passed=$PASS failed=$FAIL skipped=$SKIP"
[[ $FAIL -eq 0 ]] || exit 1
exit 0

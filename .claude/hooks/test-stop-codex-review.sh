#!/bin/bash
# test-stop-codex-review.sh - Two-sided fixture for the codex auto-review Stop
# hook, per docs/agents/guard-evidence.md: a checker needs a leg that FAILS
# when its mechanism is absent, not only a leg that passes when it works.
# #625 sat unnoticed for 12.5 hours precisely because no such fixture existed.
#
# Hermetic: isolated TMPDIR state root, isolated HOME, throwaway git repos
# whose origins claim campaign names, and a stub `codex` on PATH. No network,
# no real reviewer, no shared state. One caveat: the hook also scans the REAL
# campaign roots for index locks, so a genuinely held lock on this box fails
# legs spuriously - rerun after the lock clears.
#
# Legs A and F drive the REAL post-write tracker rather than fabricating its
# ledger: a fabricated ledger tests only the Stop hook and lets tracker
# defects (like the nested-repo ancestor-prefix bug) pass unseen.
#
#   leg A  commit-mid-turn write     -> the diff MUST reach the reviewer
#                                       (the #625 hole: HEAD-diffing sends nothing)
#   leg B  no session state          -> allow, and codex never invoked
#   leg C  unmeasurable baseline     -> block (cannot-measure is not pass)
#   leg D  CHANGES_REQUESTED verdict -> block carries the findings
#   leg E  no-net-change write       -> allow, with the explicit no-net-change note
#   leg F  outer repo, then NESTED repo committed mid-turn -> both get
#          baselines and the nested diff reaches the reviewer (migration
#          nests inside the dbatools worktree in production)
#   leg G  a repo whose origin merely ENDS in a campaign name
#          (evil.example/dataplat/dbatools.git) -> dropped from the payload,
#          out loud - suffix matching let lookalikes into the review
#   leg H  partial tracker state -> block, four shapes: .repos without .txt;
#          an EMPTY .txt; a real failed append (unwritable ledger -> exit 2
#          plus a durable .fail marker); the .fail marker alone over an
#          otherwise-healthy ledger
#   leg I  the state ROOT is a symlink -> tracker refuses (exit 2), the Stop
#          gate blocks rather than trusting ledgers under an
#          attacker-controlled root, and the symlink TARGET stays entirely
#          untouched - no ledgers, caches, or stop-guard markers leak through
#   leg J  the reviewed file is mutated DURING the review -> the CLEAN verdict
#          must block, not merely skip the cache (approval-of-vanished-code)
#   leg K  a CLEAN approval is cached, then a foreign-repo file joins the
#          ledger with the diff unchanged -> the cache must miss (scope is
#          part of the key) and the drop warning must surface
#   leg L  a foreign repo NESTED UNDER a campaign root -> the file's own git
#          toplevel decides (dropped), never the outer root's path prefix;
#          campaign-root files still resolve (function-level, extracted)
#   leg M  a file joins the write ledger WHILE the reviewer runs -> the CLEAN
#          verdict must block (the TOCTOU recheck reloads the ledger; a scope
#          captured before the review must not approve the wider one)
#   leg N  a nested repo with a recorded baseline is DELETED whole -> block;
#          the path resolves only to the outer repo, which cannot see the
#          deletion, and "no change" is exactly the wrong verdict
#   leg O  first-baseline creation is serialized: a held lock starves the
#          tracker into fail-closed (exit 2 + marker, NO baseline), and 8
#          parallel first writes yield exactly one baseline line
#   leg P  the .fail marker is a planted symlink -> the failure path must not
#          write through it, and a dangling symlink marker must still block
#   leg Q  codex unavailable AND tracker state broken -> the integrity block
#          fires BEFORE the availability advisory can allow
#   leg R  an index lock cleared during the FINAL wait reads as cleared
#          (function-level, extracted); plus leg H-e: the append verifier
#          rejects a short re-append that an older intact occurrence of the
#          same path would previously have vouched for
#
# Run: bash .claude/hooks/test-stop-codex-review.sh    (exit 0 = all legs green)
set -u

HOOK_DIR=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d) || exit 2
cleanup() { rm -r "$WORK" 2>/dev/null; }
trap cleanup EXIT
export TMPDIR="$WORK/state"
export HOME="$WORK/home"
mkdir -p "$TMPDIR" "$HOME" "$WORK/bin"
chmod 700 "$HOME"

# Stub codex: satisfies the --version probe, captures the review prompt from
# stdin, answers through -o with whatever verdict the leg asks for.
cat > "$WORK/bin/codex" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then echo "codex-stub 0.0"; exit 0; fi
out=""
prev=""
for a in "$@"; do
    [[ "$prev" == "-o" ]] && out="$a"
    prev="$a"
done
cat > "${CODEX_STUB_PROMPT_FILE:-/dev/null}"
printf '%s\n' "$@" > "${CODEX_STUB_ARGS_FILE:-/dev/null}"
if [[ -n "${CODEX_STUB_MUTATE_FILE:-}" ]]; then
    printf '# mutated-while-the-reviewer-ran\n' >> "$CODEX_STUB_MUTATE_FILE"
fi
if [[ -n "${CODEX_STUB_LEDGER_ADD:-}" && -n "${CODEX_STUB_LEDGER_FILE:-}" ]]; then
    printf '%s\n' "$CODEX_STUB_LEDGER_ADD" >> "$CODEX_STUB_LEDGER_FILE"
fi
printf 'stub finding: fixture\nVERDICT: %s\n' "${CODEX_STUB_VERDICT:-CLEAN}" > "${out:-/dev/null}"
exit 0
STUB
chmod +x "$WORK/bin/codex"
export PATH="$WORK/bin:$PATH"

REPO="$WORK/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email fixture@test
git -C "$REPO" config user.name fixture
git -C "$REPO" remote add origin https://github.com/dataplat/dbatools.git
printf 'function Get-Thing { 1 }\n' > "$REPO/thing.ps1"
git -C "$REPO" add thing.ps1
git -C "$REPO" commit -qm init
BASE=$(git -C "$REPO" rev-parse HEAD)
ORIGIN_URL="https://github.com/dataplat/dbatools.git"

STATE="$TMPDIR/claude-dbatools-hooks/session-files"
mkdir -p "$STATE"

run_hook() {    # <leg-id>  -> $OUT (stdout), $RC
    OUT=$(printf '{"session_id":"%s","transcript_path":"%s/transcript-%s.jsonl"}' "$1" "$WORK" "$1" \
        | bash "$HOOK_DIR/stop-codex-review.sh" 2>"$WORK/err-$1.log")
    RC=$?
}

track() {    # <leg-id> <file-path> - the REAL post-write tracker, not a fabrication
    printf '{"session_id":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" \
        | bash "$HOOK_DIR/post-write-track-session-files.sh"
}

FAILED=0
fail() { echo "FAIL $1"; FAILED=1; }
pass() { echo "ok   $1"; }

# ---- leg A: committed-mid-turn change must reach the reviewer ---------------
printf 'function Get-Thing { 2 } # SENTINEL_A\n' > "$REPO/thing.ps1"
track legA "$REPO/thing.ps1"
git -C "$REPO" commit -qam "mid-turn commit"
if [[ "$(cut -f1 "$STATE/legA.repos" 2>/dev/null)" == "$BASE" ]]; then
    pass "leg A: tracker recorded the pre-commit HEAD as baseline"
else
    fail "leg A: tracker did not record the pre-commit baseline"
fi
export CODEX_STUB_PROMPT_FILE="$WORK/promptA.txt"
export CODEX_STUB_ARGS_FILE="$WORK/argsA.txt"
export CODEX_STUB_VERDICT=CLEAN
run_hook legA
if grep -q 'SENTINEL_A' "$WORK/promptA.txt" 2>/dev/null; then
    pass "leg A: committed-mid-turn diff reached the reviewer"
else
    fail "leg A: committed-mid-turn diff never reached the reviewer (the #625 hole)"
fi
if grep -x -A1 -- '--disable' "$WORK/argsA.txt" 2>/dev/null | grep -qx 'hooks'; then
    pass "leg A: reviewer ran with codex hooks disabled"
else
    fail "leg A: codex invocation is missing --disable hooks"
fi
if grep -q -- '--dangerously-bypass-hook-trust' "$WORK/argsA.txt" 2>/dev/null; then
    fail "leg A: hook-trust bypass present - repo hooks would execute during review"
else
    pass "leg A: no hook-trust bypass flag in the codex invocation"
fi
if [[ "$OUT" == *'"decision":"block"'* ]]; then
    fail "leg A: CLEAN verdict still blocked the turn"
else
    pass "leg A: CLEAN verdict allowed the turn"
fi

# ---- leg B: a session that wrote nothing must stay silent and cheap ---------
export CODEX_STUB_PROMPT_FILE="$WORK/promptB.txt"
run_hook legB
if [[ -e "$WORK/promptB.txt" ]]; then
    fail "leg B: codex was invoked for a session with no tracked writes"
else
    pass "leg B: no writes -> codex not invoked"
fi
if [[ "$OUT" == *'"decision":"block"'* ]]; then
    fail "leg B: no-write session was blocked"
else
    pass "leg B: no-write session allowed"
fi

# ---- leg C: an unmeasurable baseline must block, not pass -------------------
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legC.txt"
printf '%s\t%s\t%s\n' "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "$ORIGIN_URL" "$REPO" > "$STATE/legC.repos"
export CODEX_STUB_PROMPT_FILE="$WORK/promptC.txt"
run_hook legC
if [[ "$OUT" == *'"decision":"block"'* && "$OUT" == *'COULD NOT MEASURE'* ]]; then
    pass "leg C: unmeasurable baseline blocked the turn"
else
    fail "leg C: unmeasurable baseline did not block (empty measurement read as pass)"
fi
if [[ -e "$WORK/promptC.txt" ]]; then
    fail "leg C: codex was invoked over an unmeasurable diff"
else
    pass "leg C: no codex call over an unmeasurable diff"
fi

# ---- leg D: CHANGES_REQUESTED must block with the findings ------------------
printf 'function Get-Thing { 3 } # SENTINEL_D\n' >> "$REPO/thing.ps1"
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legD.txt"
printf '%s\t%s\t%s\n' "$BASE" "$ORIGIN_URL" "$REPO" > "$STATE/legD.repos"
export CODEX_STUB_PROMPT_FILE="$WORK/promptD.txt"
export CODEX_STUB_VERDICT=CHANGES_REQUESTED
run_hook legD
if [[ "$OUT" == *'"decision":"block"'* && "$OUT" == *'CODEX AUTO-REVIEW'* ]]; then
    pass "leg D: CHANGES_REQUESTED blocked with findings"
else
    fail "leg D: CHANGES_REQUESTED did not block"
fi
git -C "$REPO" checkout -q -- thing.ps1

# ---- leg E: measured-but-unchanged must allow, out loud ---------------------
HEAD_NOW=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legE.txt"
printf '%s\t%s\t%s\n' "$HEAD_NOW" "$ORIGIN_URL" "$REPO" > "$STATE/legE.repos"
export CODEX_STUB_PROMPT_FILE="$WORK/promptE.txt"
export CODEX_STUB_VERDICT=CLEAN
run_hook legE
if [[ "$OUT" == *'"decision":"block"'* ]]; then
    fail "leg E: no-net-change session was blocked"
else
    pass "leg E: no-net-change session allowed"
fi
if [[ "$OUT" == *'no net change'* ]]; then
    pass "leg E: allow was explicit, not silent"
else
    fail "leg E: no-net-change allow was silent (empty and pass are indistinguishable again)"
fi
if [[ -e "$WORK/promptE.txt" ]]; then
    fail "leg E: codex was invoked with nothing to review"
else
    pass "leg E: no codex call with nothing to review"
fi

# ---- leg F: nested repo written after its ancestor must still be measured ---
NEST="$REPO/nested"
mkdir -p "$NEST"
git -C "$NEST" init -q -b main
git -C "$NEST" config user.email fixture@test
git -C "$NEST" config user.name fixture
git -C "$NEST" remote add origin https://github.com/potatoqualitee/migration.git
printf 'inner = 1\n' > "$NEST/inner.ps1"
git -C "$NEST" add inner.ps1
git -C "$NEST" commit -qm init
track legF "$REPO/thing.ps1"
printf 'inner = 2 # SENTINEL_F\n' > "$NEST/inner.ps1"
track legF "$NEST/inner.ps1"
git -C "$NEST" commit -qam "nested mid-turn commit"
if cut -f3 "$STATE/legF.repos" 2>/dev/null | grep -qxF "$NEST"; then
    pass "leg F: tracker gave the nested repo its own baseline"
else
    fail "leg F: nested repo baseline suppressed by its ancestor's entry"
fi
export CODEX_STUB_PROMPT_FILE="$WORK/promptF.txt"
export CODEX_STUB_VERDICT=CLEAN
run_hook legF
if grep -q 'SENTINEL_F' "$WORK/promptF.txt" 2>/dev/null; then
    pass "leg F: nested repo's committed-mid-turn diff reached the reviewer"
else
    fail "leg F: nested repo's committed-mid-turn diff vanished from review"
fi
if [[ "$OUT" == *'"decision":"block"'* ]]; then
    fail "leg F: CLEAN verdict still blocked the turn"
else
    pass "leg F: CLEAN verdict allowed the turn"
fi

# ---- leg G: a lookalike origin must not enter the review payload ------------
EVIL="$WORK/evil"
mkdir -p "$EVIL"
git -C "$EVIL" init -q -b main
git -C "$EVIL" config user.email fixture@test
git -C "$EVIL" config user.name fixture
git -C "$EVIL" remote add origin https://evil.example/dataplat/dbatools.git
printf 'x = 1\n' > "$EVIL/evil.ps1"
git -C "$EVIL" add evil.ps1
git -C "$EVIL" commit -qm init
track legG "$EVIL/evil.ps1"
printf 'x = 2 # SENTINEL_G\n' > "$EVIL/evil.ps1"
export CODEX_STUB_PROMPT_FILE="$WORK/promptG.txt"
export CODEX_STUB_VERDICT=CLEAN
run_hook legG
if grep -q 'SENTINEL_G' "$WORK/promptG.txt" 2>/dev/null; then
    fail "leg G: foreign lookalike origin's content entered the external review"
else
    pass "leg G: foreign lookalike origin kept out of the review payload"
fi
if [[ "$OUT" == *'non-campaign'* ]]; then
    pass "leg G: the dropped file was announced, not silent"
else
    fail "leg G: foreign-repo drop was silent"
fi

# ---- leg H: .repos without .txt is partial tracker state, not a quiet session
printf '%s\t-\t%s\n' "$BASE" "$REPO" > "$STATE/legH.repos"
export CODEX_STUB_PROMPT_FILE="$WORK/promptH.txt"
run_hook legH
if [[ "$OUT" == *'"decision":"block"'* && "$OUT" == *'CANNOT MEASURE'* ]]; then
    pass "leg H: lost write ledger blocked the turn"
else
    fail "leg H: .repos-without-.txt read as a quiet session (partial state passed)"
fi
if [[ -e "$WORK/promptH.txt" ]]; then
    fail "leg H: codex was invoked with no write ledger"
else
    pass "leg H: no codex call over partial tracker state"
fi
# H-b: an EMPTY .txt is a persistence failure, not a small quiet session
: > "$STATE/legHb.txt"
printf '%s\t-\t%s\n' "$BASE" "$REPO" > "$STATE/legHb.repos"
run_hook legHb
if [[ "$OUT" == *'"decision":"block"'* && "$OUT" == *'CANNOT MEASURE'* ]]; then
    pass "leg H: empty write ledger blocked the turn"
else
    fail "leg H: empty write ledger read as a quiet session (failed append passed)"
fi
# H-c: a real failed append (unwritable ledger) must exit 2 AND leave a
# durable marker - exit codes evaporate, the Stop gate needs the marker
: > "$STATE/legHc.txt"
chmod 400 "$STATE/legHc.txt"
track legHc "$REPO/thing.ps1"
TRACK_RC=$?
if [[ $TRACK_RC -eq 2 && -e "$STATE/legHc.fail" ]]; then
    pass "leg H: failed append left a durable failure marker (exit 2)"
else
    fail "leg H: failed append left no durable marker (rc=$TRACK_RC) - Stop cannot see the loss"
fi
chmod 600 "$STATE/legHc.txt"
# H-d: the marker ALONE must block, even over an otherwise-healthy ledger
HD_HEAD=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legHd.txt"
printf '%s\t-\t%s\n' "$HD_HEAD" "$REPO" > "$STATE/legHd.repos"
: > "$STATE/legHd.fail"
run_hook legHd
if [[ "$OUT" == *'"decision":"block"'* && "$OUT" == *'CANNOT MEASURE'* ]]; then
    pass "leg H: failure marker blocked despite a healthy-looking ledger"
else
    fail "leg H: failure marker ignored - an undercounting ledger was trusted"
fi
# H-e: the append verifier must reject a same-path re-append that landed
# short - an older intact occurrence must not vouch for the new one.
# Function-level: extracted from the tracker and fed a fabricated ledger
# whose second copy of the path is truncated (fault injection into a live
# printf is not portable; the verifier's contract is what is pinned here).
eval "$(awk '/^ledger_verify_append\(\) \{/,/^\}$/' "$HOOK_DIR/post-write-track-session-files.sh")"
printf '%s\n%s' "$REPO/thing.ps1" "$REPO/thi" > "$WORK/legHe-ledger"
if declare -f ledger_verify_append >/dev/null 2>&1 && ! ledger_verify_append "$WORK/legHe-ledger" "$REPO/thing.ps1" 1; then
    pass "leg H: short re-append of a known path is rejected (count must grow)"
else
    fail "leg H: an older occurrence vouched for a short re-append"
fi

# ---- leg I: a symlinked state ROOT must be refused, not written through -----
HOSTILE="$WORK/hostile"
HTARGET="$WORK/hostile-target"
mkdir -p "$HOSTILE" "$HTARGET"
ln -s "$HTARGET" "$HOSTILE/claude-dbatools-hooks"
printf '{"session_id":"legI","tool_input":{"file_path":"%s"}}' "$REPO/thing.ps1" \
    | TMPDIR="$HOSTILE" bash "$HOOK_DIR/post-write-track-session-files.sh" 2>"$WORK/err-legI-track.log"
TRACK_RC=$?
if [[ $TRACK_RC -eq 2 && ! -e "$HTARGET/session-files/legI.txt" ]]; then
    pass "leg I: tracker refused the symlinked state root (exit 2, nothing written)"
else
    fail "leg I: tracker wrote session state through a symlinked root (rc=$TRACK_RC)"
fi
export CODEX_STUB_PROMPT_FILE="$WORK/promptI.txt"
OUT=$(printf '{"session_id":"legI","transcript_path":"%s/transcript-legI.jsonl"}' "$WORK" \
    | TMPDIR="$HOSTILE" bash "$HOOK_DIR/stop-codex-review.sh" 2>"$WORK/err-legI-stop.log")
if [[ "$OUT" == *'"decision":"block"'* && "$OUT" == *'CANNOT TRUST'* ]]; then
    pass "leg I: Stop gate refused to trust state under a symlinked root"
else
    fail "leg I: Stop gate trusted ledgers under an attacker-controlled root"
fi
# Refusing the ledger is not enough: parser caches, codex probes, and
# stop-guard markers must not leak through the hostile root either.
LEAKED=$(find "$HTARGET" -mindepth 1 2>/dev/null)
if [[ -z "$LEAKED" ]]; then
    pass "leg I: hostile target entirely untouched"
else
    fail "leg I: state leaked through the hostile root: $(printf '%s' "$LEAKED" | head -3 | tr '\n' ' ')"
fi

# ---- leg J: mutation during the review must block, not just skip the cache --
printf 'function Get-Thing { 9 } # SENTINEL_J\n' > "$REPO/thing.ps1"
JHEAD=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legJ.txt"
printf '%s\t-\t%s\n' "$JHEAD" "$REPO" > "$STATE/legJ.repos"
export CODEX_STUB_PROMPT_FILE="$WORK/promptJ.txt"
export CODEX_STUB_VERDICT=CLEAN
export CODEX_STUB_MUTATE_FILE="$REPO/thing.ps1"
run_hook legJ
export CODEX_STUB_MUTATE_FILE=""
if [[ "$OUT" == *'"decision":"block"'* && "$OUT" == *'while the reviewer was running'* ]]; then
    pass "leg J: CLEAN over mutated-during-review code blocked the turn"
else
    fail "leg J: approval survived a mid-review mutation (reviewer never saw the shipped bytes)"
fi
git -C "$REPO" checkout -q -- thing.ps1

# ---- leg K: a cached approval must not transfer to a changed review scope ---
printf 'function Get-Thing { 5 } # SENTINEL_K\n' > "$REPO/thing.ps1"
KHEAD=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legK.txt"
printf '%s\t-\t%s\n' "$KHEAD" "$REPO" > "$STATE/legK.repos"
export CODEX_STUB_PROMPT_FILE="$WORK/promptK1.txt"
run_hook legK
if [[ -e "$WORK/promptK1.txt" && "$OUT" != *'"decision":"block"'* ]]; then
    pass "leg K: first run reviewed and approved"
else
    fail "leg K: first run did not produce a reviewed approval (leg setup broken)"
fi
export CODEX_STUB_PROMPT_FILE="$WORK/promptK2.txt"
run_hook legK
if [[ -e "$WORK/promptK2.txt" ]]; then
    fail "leg K: identical diff+scope was re-reviewed (clean cache never engages, so leg K proves nothing)"
else
    pass "leg K: identical diff+scope hit the clean cache"
fi
printf '%s\n' "$EVIL/evil.ps1" >> "$STATE/legK.txt"
export CODEX_STUB_PROMPT_FILE="$WORK/promptK3.txt"
run_hook legK
if [[ -e "$WORK/promptK3.txt" ]]; then
    pass "leg K: scope change busted the cached approval (re-reviewed)"
else
    fail "leg K: stale approval transferred to a changed review scope"
fi
if [[ "$OUT" == *'non-campaign'* ]]; then
    pass "leg K: the scope warning surfaced on the approval path"
else
    fail "leg K: approval swallowed the foreign-repo scope warning"
fi
git -C "$REPO" checkout -q -- thing.ps1

# ---- leg M: scope growth during the review must void the approval -----------
printf 'function Get-Thing { 6 } # SENTINEL_M\n' > "$REPO/thing.ps1"
MHEAD=$(git -C "$REPO" rev-parse HEAD)
printf 'late = 1 # SENTINEL_M2\n' > "$REPO/late.ps1"
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legM.txt"
printf '%s\t-\t%s\n' "$MHEAD" "$REPO" > "$STATE/legM.repos"
export CODEX_STUB_PROMPT_FILE="$WORK/promptM.txt"
export CODEX_STUB_VERDICT=CLEAN
export CODEX_STUB_LEDGER_ADD="$REPO/late.ps1"
export CODEX_STUB_LEDGER_FILE="$STATE/legM.txt"
run_hook legM
export CODEX_STUB_LEDGER_ADD=""
export CODEX_STUB_LEDGER_FILE=""
if [[ "$OUT" == *'"decision":"block"'* && "$OUT" == *'while the reviewer was running'* ]]; then
    pass "leg M: file tracked during the review voided the CLEAN verdict"
else
    fail "leg M: pre-review scope approved a ledger that grew during the review"
fi
rm -f "$REPO/late.ps1"
git -C "$REPO" checkout -q -- thing.ps1

# ---- leg N: whole nested-repo deletion must block, not read as no change ----
NESTGONE="$REPO/nestgone"
mkdir -p "$NESTGONE"
git -C "$NESTGONE" init -q -b main
git -C "$NESTGONE" config user.email fixture@test
git -C "$NESTGONE" config user.name fixture
git -C "$NESTGONE" remote add origin https://github.com/potatoqualitee/migration.git
printf 'gone = 1\n' > "$NESTGONE/gone.ps1"
git -C "$NESTGONE" add gone.ps1
git -C "$NESTGONE" commit -qm init
track legN "$REPO/thing.ps1"
track legN "$NESTGONE/gone.ps1"
chmod -R u+w "$NESTGONE"
rm -r "$NESTGONE"
export CODEX_STUB_PROMPT_FILE="$WORK/promptN.txt"
export CODEX_STUB_VERDICT=CLEAN
run_hook legN
if [[ "$OUT" == *'"decision":"block"'* && "$OUT" == *'COULD NOT MEASURE'* ]]; then
    pass "leg N: deleted nested repo blocked as cannot-measure"
else
    fail "leg N: nested-repo deletion measured as no change and shipped"
fi

# ---- leg O: first-baseline creation is serialized, fail-closed --------------
# A held lock must starve the tracker into exit 2 + marker with NO baseline
# recorded; a tracker without the lock sails through, which is the red side.
mkdir -p "$STATE/legO.baseline.lock"
track legO "$REPO/thing.ps1"
TRACK_RC=$?
if [[ $TRACK_RC -eq 2 && -e "$STATE/legO.fail" ]] && ! cut -f3 "$STATE/legO.repos" 2>/dev/null | grep -qxF "$REPO"; then
    pass "leg O: held baseline lock fails closed (exit 2, marker, no baseline)"
else
    fail "leg O: tracker recorded a baseline despite a held lock (rc=$TRACK_RC)"
fi
rmdir "$STATE/legO.baseline.lock" 2>/dev/null
# Parallel first writes into one repo must yield exactly one baseline line.
# Measured red on unlocked hooks: 8 simultaneous first writes all read the
# empty file before any append and recorded 8 baselines.
for _n in 1 2 3 4 5 6 7 8; do
    track legOp "$REPO/par$_n.ps1" &
done
wait
OLINES=$(cut -f3 "$STATE/legOp.repos" 2>/dev/null | grep -cxF "$REPO")
OPATHS=$(sort -u "$STATE/legOp.txt" 2>/dev/null | grep -c 'par[0-9]\.ps1$')
if [[ "$OLINES" == "1" && "$OPATHS" == "8" ]]; then
    pass "leg O: 8 parallel first writes -> one baseline line, all 8 paths intact"
else
    fail "leg O: parallel first writes corrupted session state (baselines=$OLINES paths=$OPATHS)"
fi

# ---- leg P: a planted symlink .fail marker must not become a write-through --
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legP.txt"
chmod 400 "$STATE/legP.txt"
ln -s "$WORK/evil-marker-target" "$STATE/legP.fail"
track legP "$REPO/other-p.ps1"
TRACK_RC=$?
if [[ $TRACK_RC -eq 2 && ! -e "$WORK/evil-marker-target" ]]; then
    pass "leg P: failure path refused to write through the planted symlink"
else
    fail "leg P: persist_failure wrote through a symlinked marker (rc=$TRACK_RC)"
fi
chmod 600 "$STATE/legP.txt"
# A marker that survives only as a DANGLING symlink still names a failure;
# -e follows the link and misses it, so the Stop gate must check -L too.
PHEAD=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legPs.txt"
printf '%s\t-\t%s\n' "$PHEAD" "$REPO" > "$STATE/legPs.repos"
ln -s "$WORK/absent-marker-target" "$STATE/legPs.fail"
run_hook legPs
if [[ "$OUT" == *'"decision":"block"'* && "$OUT" == *'CANNOT MEASURE'* ]]; then
    pass "leg P: dangling symlink marker still blocked the turn"
else
    fail "leg P: a dangling symlink marker was invisible to the Stop gate"
fi

# ---- leg Q: broken tracker state must block even with no reviewer installed -
mkdir -p "$WORK/nocodexbin"
printf '#!/bin/bash\nexit 127\n' > "$WORK/nocodexbin/codex"
chmod +x "$WORK/nocodexbin/codex"
rm -f "$TMPDIR/claude-dbatools-hooks/codex.cached"
QHEAD=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legQ.txt"
printf '%s\t-\t%s\n' "$QHEAD" "$REPO" > "$STATE/legQ.repos"
: > "$STATE/legQ.fail"
OUT=$(printf '{"session_id":"legQ","transcript_path":"%s/transcript-legQ.jsonl"}' "$WORK" \
    | PATH="$WORK/nocodexbin:$PATH" bash "$HOOK_DIR/stop-codex-review.sh" 2>"$WORK/err-legQ.log")
if [[ "$OUT" == *'"decision":"block"'* && "$OUT" == *'CANNOT MEASURE'* ]]; then
    pass "leg Q: integrity block fired before the no-reviewer advisory"
else
    fail "leg Q: a codex-less allow covered a session with broken tracker state"
fi

# ---- leg L: a nested foreign repo must not ride a campaign root's path ------
# Function-level: campaign_file_root is extracted verbatim from the hook and
# called with a test-owned literal root, because the production literals
# cannot safely host a foreign repo in a fixture.
FAKE="$WORK/fakecampaign"
mkdir -p "$FAKE"
git -C "$FAKE" init -q -b main
git -C "$FAKE" config user.email fixture@test
git -C "$FAKE" config user.name fixture
printf 'ok = 1\n' > "$FAKE/ok.ps1"
git -C "$FAKE" add ok.ps1
git -C "$FAKE" commit -qm init
NESTEVIL="$FAKE/vendor/evil"
mkdir -p "$NESTEVIL"
git -C "$NESTEVIL" init -q -b main
git -C "$NESTEVIL" config user.email fixture@test
git -C "$NESTEVIL" config user.name fixture
printf 'x = 1\n' > "$NESTEVIL/x.ps1"
git -C "$NESTEVIL" add x.ps1
git -C "$NESTEVIL" commit -qm init
eval "$(awk '/^campaign_file_root\(\) \{/,/^\}$/' "$HOOK_DIR/stop-codex-review.sh")"
CAMPAIGN_ROOTS=("$FAKE")
campaign_file_root "$NESTEVIL/x.ps1" >/dev/null
if [[ $? -eq 2 ]]; then
    pass "leg L: nested foreign repo under a campaign root is dropped, not reviewed"
else
    fail "leg L: nested foreign repo rode the campaign root's path into review scope"
fi
LROOT=$(campaign_file_root "$FAKE/ok.ps1")
if [[ $? -eq 0 && "$LROOT" == "$FAKE" ]]; then
    pass "leg L: campaign-root file still resolves to its root"
else
    fail "leg L: campaign-root file no longer resolves (scope regression)"
fi

# ---- leg W: one AUTOMATIC round per session, and the free block still BLOCKS -
# The value of step 4a is that it moved the SPEND without moving the GATE, so
# both halves get asserted separately: a leg that only checked "no second codex
# call" would pass just as well if the hook had started allowing the turn, which
# is the bypass this campaign keeps re-learning.
printf 'function Get-Thing { 4 } # SENTINEL_W1\n' > "$REPO/thing.ps1"
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legW.txt"
printf '%s\t%s\t%s\n' "$BASE" "$ORIGIN_URL" "$REPO" > "$STATE/legW.repos"
export CODEX_STUB_VERDICT=CHANGES_REQUESTED

export CODEX_STUB_PROMPT_FILE="$WORK/promptW1.txt"
run_hook legW
if [[ "$OUT" == *'"decision":"block"'* && -e "$WORK/promptW1.txt" ]]; then
    pass "leg W: round 1 spends the automatic codex call and blocks"
else
    fail "leg W: round 1 did not review-and-block -- the rest of this leg proves nothing"
fi

# Round 2, same diff: the gate must hold, and it must hold for free.
export CODEX_STUB_PROMPT_FILE="$WORK/promptW2.txt"
run_hook legW
if [[ "$OUT" == *'"decision":"block"'* ]]; then
    pass "leg W: round 2 still BLOCKS -- moving the spend did not reopen the bypass"
else
    fail "leg W: round 2 allowed the turn to end with no CLEAN verdict -- this is the removed per-diff bypass, back again"
fi
if [[ -e "$WORK/promptW2.txt" ]]; then
    fail "leg W: round 2 called codex anyway -- the automatic-round budget does nothing"
else
    pass "leg W: round 2 called no codex -- the block is free"
fi
RECHECK_PATH=$(printf '%s' "$OUT" | grep -o '[^ "\\]*_codex-review\.recheck' | head -1)
if [[ -n "$RECHECK_PATH" ]]; then
    pass "leg W: the block names the recheck marker to touch"
else
    fail "leg W: the block did not name a recheck path -- there is no way out of it"
fi

# Perturbation control for the assertion above. "No codex call" is also what the
# clean cache and every early exit produce, so the silence has to be shown to
# come from the budget marker specifically: remove it, replay the SAME round,
# and codex must run again. Without this, leg W would pass unchanged against a
# build with step 4a deleted.
AUTOSPENT_PATH="${RECHECK_PATH%.recheck}.autospent"
if [[ -f "$AUTOSPENT_PATH" ]]; then
    mv "$AUTOSPENT_PATH" "$AUTOSPENT_PATH.parked"
    export CODEX_STUB_PROMPT_FILE="$WORK/promptW2c.txt"
    run_hook legW
    if [[ -e "$WORK/promptW2c.txt" ]]; then
        pass "leg W control: with the budget marker gone the same round reviews again -- the silence above was the budget, not a cache"
    else
        fail "leg W control: the round stayed silent with no budget marker, so leg W is measuring something else entirely and cannot fail"
    fi
    rm -f "$AUTOSPENT_PATH.parked"
else
    fail "leg W control: no budget marker was written, so the free block is UNEXPLAINED and its assertion is unverified"
fi

# A NEW diff must not buy a fresh automatic round: "runs once" is per session,
# and the cumulative payload means every turn's diff is a new one.
printf 'function Get-Thing { 5 } # SENTINEL_W3\n' > "$REPO/thing.ps1"
export CODEX_STUB_PROMPT_FILE="$WORK/promptW3.txt"
run_hook legW
if [[ "$OUT" == *'"decision":"block"'* && ! -e "$WORK/promptW3.txt" ]]; then
    pass "leg W: a changed diff does not buy another automatic round"
else
    fail "leg W: a changed diff bought a fresh codex call -- the budget is per-diff, so it caps nothing"
fi

# The recheck marker is the way out, and it must be consumed by the round it buys.
if [[ -n "$RECHECK_PATH" ]]; then
    : > "$RECHECK_PATH"
    export CODEX_STUB_PROMPT_FILE="$WORK/promptW4.txt"
    export CODEX_STUB_VERDICT=CLEAN
    run_hook legW
    if [[ -e "$WORK/promptW4.txt" ]]; then
        pass "leg W: touching the recheck marker runs a full review"
    else
        fail "leg W: the recheck marker did not trigger a review -- the block is inescapable"
    fi
    if [[ "$OUT" != *'"decision":"block"'* ]]; then
        pass "leg W: a CLEAN recheck releases the turn"
    else
        fail "leg W: a CLEAN recheck still blocked"
    fi
    if [[ ! -e "$RECHECK_PATH" ]]; then
        pass "leg W: the marker is consumed, so one touch buys one round"
    else
        fail "leg W: the marker survived its round -- one touch re-enables automatic reviews for the rest of the session"
    fi
else
    fail "leg W: no recheck path to exercise, so the escape hatch is UNVERIFIED on this run"
fi
git -C "$REPO" checkout -q -- thing.ps1
unset CODEX_STUB_VERDICT CODEX_STUB_PROMPT_FILE

# ---- leg W2: a planted symlink .autospent must not become a write-through ----
# Same class leg P covers for .fail markers. The path is predictable and lives
# under a world-writable temp root, so a plain redirect would follow the link and
# overwrite whatever it names. Two halves, because either alone passes on a build
# that got the other wrong: nothing may be written THROUGH the link, and the link
# must not read as a spent budget (which would buy a free block with no review).
printf 'function Get-Thing { 6 } # SENTINEL_W2A\n' > "$REPO/thing.ps1"
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legW2.txt"
printf '%s\t%s\t%s\n' "$BASE" "$ORIGIN_URL" "$REPO" > "$STATE/legW2.repos"
export CODEX_STUB_VERDICT=CHANGES_REQUESTED

# Round 1 spends the budget honestly, so the marker path is the live one. Round 2
# is what NAMES it: round 1's block is the ordinary findings block, and only the
# already-spent block prints the recheck path.
export CODEX_STUB_PROMPT_FILE="$WORK/promptW2a.txt"
run_hook legW2
export CODEX_STUB_PROMPT_FILE="$WORK/promptW2a2.txt"
run_hook legW2
W2_RECHECK=$(printf '%s' "$OUT" | grep -o '[^ "\\]*_codex-review\.recheck' | head -1)
W2_AUTOSPENT="${W2_RECHECK%.recheck}.autospent"
if [[ -n "$W2_RECHECK" && -f "$W2_AUTOSPENT" ]]; then
    pass "leg W2 setup: round 1 spent the budget and wrote a real marker"
else
    fail "leg W2 setup: no budget marker was written, so the symlink legs below prove nothing"
fi

# Replace the real marker with a symlink at an absent target and force a write.
rm -f "$W2_AUTOSPENT"
ln -s "$WORK/evil-autospent-target" "$W2_AUTOSPENT"
: > "$W2_RECHECK"
printf 'function Get-Thing { 7 } # SENTINEL_W2B\n' > "$REPO/thing.ps1"
export CODEX_STUB_PROMPT_FILE="$WORK/promptW2b.txt"
run_hook legW2
if [[ ! -e "$WORK/evil-autospent-target" ]]; then
    pass "leg W2: mark_autospent refused to write through the planted symlink"
else
    fail "leg W2: mark_autospent wrote through a symlinked marker -- arbitrary file overwrite"
fi
if [[ "$OUT" == *'"decision":"block"'* ]]; then
    pass "leg W2: the turn still BLOCKS with an untrustworthy budget marker"
else
    fail "leg W2: a hostile marker released the turn"
fi

# The link must not read as a spent budget. With it in place and no recheck
# marker, the round must still REVIEW rather than take the free-block branch.
rm -f "$W2_RECHECK"
rm -f "$W2_AUTOSPENT"
ln -s "$WORK/evil-autospent-target2" "$W2_AUTOSPENT"
printf 'function Get-Thing { 8 } # SENTINEL_W2C\n' > "$REPO/thing.ps1"
export CODEX_STUB_PROMPT_FILE="$WORK/promptW2c2.txt"
run_hook legW2
if [[ -e "$WORK/promptW2c2.txt" ]]; then
    pass "leg W2: a symlinked marker does not read as a spent budget -- the review still runs"
else
    fail "leg W2: a planted symlink bought a free block with no review -- the check was made unable to run"
fi
rm -f "$W2_AUTOSPENT"
git -C "$REPO" checkout -q -- thing.ps1
unset CODEX_STUB_VERDICT CODEX_STUB_PROMPT_FILE

# ---- leg W3: a DIRECTORY at the marker path must be refused, not filled ------
# `mv -f file dir` moves the file INSIDE dir rather than failing, so a rename-
# based marker write leaves the marker unwritten AND litters the path. The
# emptiness assertion is the load-bearing one: the other two pass just as well on
# a build that quietly deposited a file in there, which is how this shipped once.
printf 'function Get-Thing { 9 } # SENTINEL_W3A\n' > "$REPO/thing.ps1"
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legW3.txt"
printf '%s\t%s\t%s\n' "$BASE" "$ORIGIN_URL" "$REPO" > "$STATE/legW3.repos"
export CODEX_STUB_VERDICT=CHANGES_REQUESTED
export CODEX_STUB_PROMPT_FILE="$WORK/promptW3a.txt"
run_hook legW3
export CODEX_STUB_PROMPT_FILE="$WORK/promptW3a2.txt"
run_hook legW3
W3_RECHECK=$(printf '%s' "$OUT" | grep -o '[^ "\\]*_codex-review\.recheck' | head -1)
W3_AUTOSPENT="${W3_RECHECK%.recheck}.autospent"
if [[ -n "$W3_RECHECK" ]]; then
    rm -f "$W3_AUTOSPENT"
    mkdir -p "$W3_AUTOSPENT"          # a directory: -f is false, writing to it fails
    printf 'function Get-Thing { 10 } # SENTINEL_W3B\n' > "$REPO/thing.ps1"
    export CODEX_STUB_PROMPT_FILE="$WORK/promptW3b.txt"
    run_hook legW3
    if [[ -e "$WORK/promptW3b.txt" ]]; then
        pass "leg W3: an unwritable marker does not suppress the review itself"
    else
        fail "leg W3: no review ran, so this leg is measuring the wrong thing"
    fi
    if [[ "$OUT" == *'CANNOT BOUND ITS ROUNDS'* && "$OUT" == *'"decision":"block"'* ]]; then
        pass "leg W3: the block says the round could not be recorded, and still blocks"
    else
        fail "leg W3: the marker write failed silently -- the next turn spends another review with no warning"
    fi
    if rmdir "$W3_AUTOSPENT" 2>/dev/null; then
        pass "leg W3: the directory was left EMPTY -- nothing was moved inside it"
    else
        fail "leg W3: the marker write deposited a file INSIDE the directory -- unwritten marker plus a littered path"
    fi
else
    fail "leg W3: no marker path resolved, so directory-marker handling is UNVERIFIED on this run"
fi
git -C "$REPO" checkout -q -- thing.ps1
unset CODEX_STUB_VERDICT CODEX_STUB_PROMPT_FILE

# ---- leg W4: the marker rename must never dereference a symlink -------------
# The -L pre-check cannot close a swap that lands AFTER it; no pre-check can.
# What makes that window harmless is that the rename itself cannot follow a link,
# so THAT is what gets asserted here.
#
# The race is not reproducible in a fixture - there is no way to land a swap
# between two adjacent shell commands on demand - and this leg does not pretend
# otherwise. It proves the property the window depends on, on this box.
MVDIR="$WORK/mvT"
rm -rf "$MVDIR"; mkdir -p "$MVDIR/victim"
printf 'payload' > "$MVDIR/src"
ln -s "$MVDIR/victim" "$MVDIR/link"
if mv -fT "$MVDIR/src" "$MVDIR/link" 2>/dev/null &&
   [[ -z "$(ls -A "$MVDIR/victim" 2>/dev/null)" && ! -L "$MVDIR/link" && -f "$MVDIR/link" ]]; then
    pass "leg W4: the rename replaces a symlink-to-directory instead of writing into it"
else
    fail "leg W4: the rename dereferenced a symlinked directory on this box -- the marker write has no safe form here"
fi

# Negative control. Without it the assertion above would pass just as well on a
# box where NOTHING dereferences, proving nothing about why -T is there.
rm -rf "$MVDIR"; mkdir -p "$MVDIR/victim"
printf 'payload' > "$MVDIR/src"
ln -s "$MVDIR/victim" "$MVDIR/link"
mv -f "$MVDIR/src" "$MVDIR/link" 2>/dev/null
if [[ -e "$MVDIR/victim/src" ]]; then
    pass "leg W4 control: the same rename WITHOUT -T does write through the symlink"
else
    fail "leg W4 control: plain mv did not dereference either, so leg W4 is not measuring the flag at all"
fi

# Function level: mark_autospent driven directly at a symlinked marker path.
rm -rf "$MVDIR"; mkdir -p "$MVDIR/victim"
eval "$(awk '/^mark_autospent\(\) \{/,/^\}$/' "$HOOK_DIR/stop-codex-review.sh")"
if declare -f mark_autospent >/dev/null 2>&1; then
    AUTOSPENT_FILE="$MVDIR/marker"
    PAYLOAD_HASH="deadbeefdeadbeef"
    AUTOSPENT_WARN=""
    ln -s "$MVDIR/victim" "$AUTOSPENT_FILE"
    mark_autospent
    if [[ -z "$(ls -A "$MVDIR/victim" 2>/dev/null)" ]]; then
        pass "leg W4: mark_autospent put nothing inside the directory a symlinked marker pointed at"
    else
        fail "leg W4: mark_autospent wrote into the directory behind a symlinked marker"
    fi
    if [[ "$AUTOSPENT_WARN" == *'CANNOT BOUND ITS ROUNDS'* ]]; then
        pass "leg W4: and it said out loud that the round could not be recorded"
    else
        fail "leg W4: the marker write failed silently at a symlinked path"
    fi
    unset AUTOSPENT_FILE PAYLOAD_HASH AUTOSPENT_WARN
else
    fail "leg W4: mark_autospent could not be extracted, so the function-level half did not run"
fi
rm -rf "$MVDIR"

# ---- leg R: a lock cleared during the FINAL wait must read as cleared -------
# Function-level: wait_for_index_locks is extracted verbatim; the lock is
# removed ~12s in, inside the third 5s wait, so only a rescan AFTER that wait
# can see it clear. Costs ~15s of wall clock - that is the point.
LOCKREPO="$WORK/lockrepo"
mkdir -p "$LOCKREPO/.git"
: > "$LOCKREPO/.git/index.lock"
eval "$(awk '/^wait_for_index_locks\(\) \{/,/^\}$/' "$HOOK_DIR/stop-codex-review.sh")"
CAMPAIGN_ROOTS=("$LOCKREPO")
LOCKED_ROOT="never-scanned"
( sleep 12; rm -f "$LOCKREPO/.git/index.lock" ) &
LOCKCLEAR_PID=$!
if declare -f wait_for_index_locks >/dev/null 2>&1; then
    wait_for_index_locks
fi
wait "$LOCKCLEAR_PID" 2>/dev/null
if [[ -z "$LOCKED_ROOT" ]]; then
    pass "leg R: lock cleared during the final wait reads as cleared"
else
    fail "leg R: stale scan reported a cleared lock as still held (LOCKED_ROOT=$LOCKED_ROOT)"
fi

exit "$FAILED"

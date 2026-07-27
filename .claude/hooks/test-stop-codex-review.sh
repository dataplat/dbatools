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

exit "$FAILED"

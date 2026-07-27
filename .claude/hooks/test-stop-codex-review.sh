#!/bin/bash
# test-stop-codex-review.sh - Two-sided fixture for the codex auto-review Stop
# hook, per docs/agents/guard-evidence.md: a checker needs a leg that FAILS
# when its mechanism is absent, not only a leg that passes when it works.
# #625 sat unnoticed for 12.5 hours precisely because no such fixture existed.
#
# Hermetic: isolated TMPDIR state root, isolated HOME, a throwaway git repo
# whose origin claims dataplat/dbatools, and a stub `codex` on PATH. No
# network, no real reviewer, no shared state. One caveat: the hook also scans
# the REAL campaign roots for index locks, so a genuinely held lock on this
# box fails legs spuriously - rerun after the lock clears.
#
#   leg A  commit-mid-turn write     -> the diff MUST reach the reviewer
#                                       (the #625 hole: HEAD-diffing sends nothing)
#   leg B  no session state          -> allow, and codex never invoked
#   leg C  unmeasurable baseline     -> block (cannot-measure is not pass)
#   leg D  CHANGES_REQUESTED verdict -> block carries the findings
#   leg E  no-net-change write       -> allow, with the explicit no-net-change note
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

FAILED=0
fail() { echo "FAIL $1"; FAILED=1; }
pass() { echo "ok   $1"; }

# ---- leg A: committed-mid-turn change must reach the reviewer ---------------
printf 'function Get-Thing { 2 } # SENTINEL_A\n' > "$REPO/thing.ps1"
git -C "$REPO" commit -qam "mid-turn commit"
printf '%s\n' "$REPO/thing.ps1" > "$STATE/legA.txt"
printf '%s\t%s\t%s\n' "$BASE" "$ORIGIN_URL" "$REPO" > "$STATE/legA.repos"
export CODEX_STUB_PROMPT_FILE="$WORK/promptA.txt"
export CODEX_STUB_VERDICT=CLEAN
run_hook legA
if grep -q 'SENTINEL_A' "$WORK/promptA.txt" 2>/dev/null; then
    pass "leg A: committed-mid-turn diff reached the reviewer"
else
    fail "leg A: committed-mid-turn diff never reached the reviewer (the #625 hole)"
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

exit "$FAILED"

#!/bin/bash
# lib-protected-surface.sh - One definition of "the verification surface",
# shared by every guard that defends it.
#
# WHY THIS FILE EXISTS
#
# The campaign's scars are not stories about someone deleting a checker. The
# forensic record (git log -S across both code repos, 2026-07-10..25) finds
# zero instances of --no-verify, chmod -x, sed -i, or a removed checker script.
# What it finds instead is four shapes of the SAME defect - a check that could
# not fail, indistinguishable from a check that passed:
#
#   fail-open at birth  #208/#249  printed "FAIL", never set a nonzero exit
#   vacuous corpus      #75        four legs green over an empty run
#   silent scope loss   2026-07-21 the codex review lived only in the code
#                                  repos; the fleet moved to migration-rooted
#                                  sessions and it stopped firing for 3 days
#   wrong artifact      #57/#231   993 rows sealed by instruments that were
#                                  measuring the PowerShell function, not the
#                                  compiled cmdlet
#
# So the surface below is deliberately NOT just "the hook scripts". It is every
# file whose quiet weakening would let a red result read as green.
#
# MATCHING IS BY PATH SUFFIX, NOT PREFIX - on purpose. This repo is reachable
# as /mnt/c/github/dbatools/migration, as /mnt/wsl/docker-desktop-bind-mounts/
# .../migration, and as C:\github\dbatools\migration through tool_input. A
# prefix rule would silently stop matching under one of those spellings, which
# is precisely the 3-day scope-loss bug above. Suffix matching also means these
# guards keep working when copied into ../dbatools and ../dbatools.library.

if [[ -n "${_LIB_PROTECTED_SURFACE_LOADED:-}" ]]; then
    return 0
fi
_LIB_PROTECTED_SURFACE_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/lib-hook-common.sh"

# surface_norm <path> - canonical comparison form: forward slashes, lowercase.
# Lowercasing everywhere (not just on Windows, as hook_normalize_path does) is
# correct here because these are all ASCII repo paths and the same file arrives
# spelled C:\GitHub\... and /mnt/c/github/... in the same session.
surface_norm() {
    printf '%s' "${1//\\//}" | tr '[:upper:]' '[:lower:]'
}

# surface_classify <path> - echo the role of a protected path, or nothing.
#
# Roles:
#   hook     an executable checker, or the library one sources
#   wiring   the settings file that decides whether checkers run at all
#   gate     the code that decides PASS / FAIL / SKIPPED
#   verdict  a gate artifact; only the gate may author these
#   tracker  the row inventory; DONE here is the campaign's output claim
surface_classify() {
    local p
    p=$(surface_norm "$1")

    # Every pattern below is anchored with a leading */, which cannot match a
    # RELATIVE path: ".claude/hooks/x.sh" has no slash before ".claude", so the
    # glob fails and the file reads as unprotected. The Edit-side guards never
    # exposed this because tool_input.file_path is always absolute - but the
    # Bash guard classifies tokens lifted straight out of a command line, where
    # "rm .claude/hooks/stop-codex-review.sh" is the normal spelling. That gap
    # made every file-tampering check silently pass, which is the same
    # fail-open shape as #208: a check that ran, reported nothing, and could
    # not have reported anything.
    [[ "$p" != /* ]] && p="/$p"

    case "$p" in
        # ---- the guards themselves, and everything they source -------------
        # Self-protection is not vanity. Until now the removal guard was the
        # one file in the surface that nothing defended, so a single edit to
        # it disarmed every other protection at once.
        #
        # The whole directory is covered, not just *.sh, for two reasons:
        # checker-manifest.sha256 lives here and is the tripwire's baseline,
        # and a command can target the DIRECTORY rather than any file in it -
        # "git checkout -- .claude/hooks/" reverts every guard at once and
        # matches no *.sh pattern at all.
        */.claude/hooks|*/.claude/hooks/)   printf 'hook'; return 0 ;;
        */.claude/hooks/*)                  printf 'hook'; return 0 ;;
        */tools/claude-bash-guard.sh)       printf 'hook'; return 0 ;;

        # The adversarial plan reviewer. It is a checker that happens to be
        # written as a skill rather than a shell script: no gocodex session may
        # implement a plan without its verdict, so deleting it or gutting its
        # invocation removes the only independent check on every defect fix.
        #
        # This case is why the entry works at all. surface_markers has carried a
        # "claude -p" contract for the reviewer since 2026-07-25, but classify
        # never recognized .claude/skills/**, and the removal guard returns at
        # its role check LONG before it reads a marker - so that contract was
        # dead code for its whole life and would have reported nothing while
        # reading exactly like a guard that passed. Found 2026-07-26 while
        # retiring the Claude-side gocodex worker skill the entry pointed at.
        */.claude/skills/reviewme/skill.md) printf 'hook'; return 0 ;;

        # ---- whether the hooks are wired at all ----------------------------
        */.claude/settings.json)      printf 'wiring'; return 0 ;;
        */.claude/settings.local.json) printf 'wiring'; return 0 ;;

        # ---- the code that decides PASS/FAIL -------------------------------
        */tools/gatesteptable.ps1)              printf 'gate'; return 0 ;;
        */tools/test-migratedcommand.ps1)       printf 'gate'; return 0 ;;
        */tools/invoke-gatewithworkstationsteps.ps1) printf 'gate'; return 0 ;;
        */tools/invoke-gatelocked.ps1)          printf 'gate'; return 0 ;;
        */tools/gatelock.psm1)                  printf 'gate'; return 0 ;;
        */tools/switch-commandexport.ps1)       printf 'gate'; return 0 ;;
        */tools/test-sealevidence.ps1)          printf 'gate'; return 0 ;;
        */tools/audit-flipbeforepass.ps1)       printf 'gate'; return 0 ;;
        */tools/test-gate*precondition.ps1)     printf 'gate'; return 0 ;;

        # ---- artifacts and claims ------------------------------------------
        # Directory forms included for the same reason as the hooks dir: the
        # destructive shapes worth catching aim at the folder, not one file.
        */logs/verdicts|*/logs/verdicts/)   printf 'verdict'; return 0 ;;
        */logs/verdicts/*)                  printf 'verdict'; return 0 ;;
        */trackers|*/trackers/)             printf 'tracker'; return 0 ;;
        */trackers/*.md)                    printf 'tracker'; return 0 ;;
    esac
    return 0
}

# surface_markers <path> - literal strings that must survive an edit to this
# file. One per line. Empty means "no marker contract, other checks still
# apply".
#
# A marker is chosen to be the thing whose absence means the check cannot run
# at all - not merely a nice-to-have. Keep them few; a long list turns the
# guard into a nuisance that blocks ordinary work, which costs more than the
# defect it prevents.
surface_markers() {
    local p
    p=$(surface_norm "$1")

    case "$p" in
        */.claude/settings.json)
            # Each of these is a hook that cannot fire if its wiring is gone.
            printf '%s\n' \
                "stop-codex-review.sh" \
                "pretooluse-checker-removal-guard.sh" \
                "pretooluse-verdict-tracker-guard.sh" \
                "pretooluse-bash-tamper-guard.sh" \
                "stop-checker-integrity.sh"
            ;;
        # "codex" is the reviewer itself. CAMPAIGN_ROOTS is the SCOPE it reviews,
        # and scope loss is how this gate actually died: the root used to be
        # derived from cwd (`git rev-parse --show-toplevel`), so every file
        # written outside the session's own repo fell out of the review set. The
        # hook ran, reported nothing, and could not have reported anything -
        # dead 2026-07-20..24, four days, found by gomanager and only because
        # someone went looking. A reviewer with the wrong scope is worse than no
        # reviewer: it produces a CLEAN verdict over the files it never saw.
        */stop-codex-review.sh)          printf '%s\n' "codex" "CAMPAIGN_ROOTS" ;;
        */run-gocodex-fleet.ps1)         printf '%s\n' "codex exec" ;;
        */lib-stop-guard.sh)             printf '%s\n' "emit_stop_block" ;;
        */pretooluse-checker-removal-guard.sh)
                                         printf '%s\n' "surface_classify" ;;
        */pretooluse-verdict-tracker-guard.sh)
                                         printf '%s\n' "surface_classify" ;;
        */pretooluse-bash-tamper-guard.sh)
                                         printf '%s\n' "surface_classify" ;;
        */verify-checker-integrity.sh)   printf '%s\n' "sha256" ;;

        # The gate's decision points. Removing any of these names means the
        # verdict is computed by something else, or not at all.
        */tools/gatesteptable.ps1)
            printf '%s\n' "Get-GateCoreStepIds" "Assert-GateStepTable" ;;
        */tools/test-migratedcommand.ps1)
            # Resolve-GateStepOutcome maps a step result to PASS/FAIL/SKIPPED.
            # corePassed is the "every core step must be present AND PASS"
            # clause - the half that catches a core step which never ran.
            printf '%s\n' "Resolve-GateStepOutcome" "corePassed" "Test-GatePesterArtifact" ;;
        */tools/switch-commandexport.ps1)
            printf '%s\n' "Test-GateVerdictReady" ;;
        */tools/gatelock.psm1)
            printf '%s\n' "Assert-NoLibraryEditLease" ;;
        # The reviewer skill. "claude -p" is the invocation a codex session
        # makes at step 3 - without it the caller has nothing to call. "APPROVED"
        # is the verdict token the caller parses; a reviewer that can no longer
        # say it is a review step that can never pass, which fails closed but
        # still means the contract is gone.
        #
        # This entry used to name .claude/skills/gocodex/SKILL.md, the
        # Claude-flavored copy of the codex worker pipeline. That skill made
        # /gocodex-in-Claude shell out to claude -p - a model reviewing itself,
        # at double the tokens, for none of the independence the step buys. It
        # was retired 2026-07-26; the codex fleet still crosses engines, which
        # was always the point.
        */.claude/skills/reviewme/skill.md)
            printf '%s\n' "claude -p" "APPROVED" ;;
    esac
}

# surface_mincounts <path> - "REGEX<TAB>MINIMUM" lines. The number of matches
# in the proposed content must not fall below MINIMUM.
#
# This is the check a marker cannot make. GateStepTable.ps1 declares which
# steps are core by tagging each row Kind = "core"; Assert-GateStepTable only
# refuses ZERO core rows, so retagging eight of the nine as "conditional"
# leaves every marker intact, every function present, and quietly shrinks what
# PASS means. Nine is the count as of be91f349 (2026-07-24), when unitPs7 and
# unitPs51 were promoted to core.
surface_mincounts() {
    local p
    p=$(surface_norm "$1")

    case "$p" in
        */tools/gatesteptable.ps1)
            printf '%s\t%s\n' 'Kind[[:space:]]*=[[:space:]]*"core"' 9
            ;;

        # The review scope: three campaign repos, three indented absolute-path
        # entries in CAMPAIGN_ROOTS. The marker alone cannot hold this - keeping
        # the NAME while shrinking the list back to one cwd-derived root
        # (CAMPAIGN_ROOTS=("$(git rev-parse --show-toplevel)")) satisfies every
        # marker, passes every guard, and silently restores the exact blindness
        # that left this hook reviewing nothing for four days. Same failure the
        # nine-core-steps count above exists to catch, in a different file.
        #
        # Anchored on leading whitespace so it counts the ARRAY ENTRIES only:
        # REPO_ROOT= and CODEX_CWD= sit at column 0 and must not pad the count.
        */stop-codex-review.sh)
            printf '%s\t%s\n' '^[[:space:]]+"/mnt/c/github' 3
            ;;
    esac
}

# surface_disable_shapes - regexes for "this line turns a check off", tested
# ONLY against text an edit ADDS to a protected file. Newly introduced, not
# pre-existing: several of these legitimately appear in code that is already
# there, and re-flagging them would block every unrelated edit to the file.
#
# The first entry is the exact shape of dea2e5ea7 ("disable hooks for now"),
# which put `exit 0` at line 2 of thirteen hook scripts rather than fixing the
# errors underneath. That is the only confirmed instance in this campaign's
# history of a checker being switched off by editing it.
#
# The `exit 0` pattern is anchored at COLUMN ZERO, and that is load-bearing.
# An indented `exit 0` is ordinary control flow - the normal way a shell
# function or an `if` block returns success - and matching it flagged every
# well-formed hook in this directory, including the first draft of
# stop-checker-integrity.sh. Only an UNCONDITIONAL top-level exit near the top
# of the file is the dea2e5ea7 shape. A guard that blocks correct code gets
# switched off, which would make it the very thing it exists to prevent.
surface_disable_shapes() {
    printf '%s\n' \
        '^exit[[:space:]]+0[[:space:]]*(#.*)?$' \
        '^[[:space:]]*return[[:space:]]+0[[:space:]]*#[[:space:]]*(disable|skip|bypass|temporar)' \
        'if[[:space:]]*\([[:space:]]*\$false[[:space:]]*\)' \
        'if[[:space:]]*\([[:space:]]*0[[:space:]]*\)[[:space:]]*(\{|then)' \
        '\|\|[[:space:]]*true[[:space:]]*$' \
        '--no-verify' \
        'catch[[:space:]]*\{[[:space:]]*\}' \
        'continue-on-error[[:space:]]*:[[:space:]]*true'
}

# surface_is_early_exit <content> - true when a whole-file Write carries the
# dea2e5ea7 shape: an unconditional `exit 0` that stops the checker from
# reaching its own checks. Used on the Write path, where there is no
# old_string to diff the addition against.
#
# "In the first 15 body lines" was the whole rule until 2026-07-26, and it
# could not tell a DISABLING exit from a CLOSING one. Every well-formed short
# hook ends in `exit 0`, so on any hook under ~15 body lines the rule fired on
# the last line of a perfectly good file - it refused to let
# post-write-track-session-files.sh (nine body lines, closing `exit 0`) be
# installed in dbatools.library at all, and migration could not have rewritten
# its own committed copy either. That is the "guard that blocks correct code
# gets switched off" failure warned about in surface_disable_shapes above,
# which is the one outcome this file cannot afford.
#
# Two shapes, both of which genuinely leave a checker unable to report:
surface_is_early_exit() {
    local body n_body idx
    body=$(printf '%s' "$1" | grep -vE '^[[:space:]]*(#|$)')
    [[ -n "$body" ]] || return 1
    n_body=$(printf '%s\n' "$body" | grep -c '')

    # 1. GUTTED: the body IS the exit. Nothing is left that could ever report,
    #    which the positional rule below cannot see, because with no following
    #    line there is no "early" to be early to.
    if (( n_body <= 2 )) && printf '%s\n' "$body" | grep -qE '^exit[[:space:]]+0[[:space:]]*(#.*)?$'; then
        return 0
    fi

    # 2. SHORT-CIRCUITED: an unconditional top-level `exit 0` up top WITH BODY
    #    STILL BELOW IT. This is dea2e5ea7 exactly - the checks stay in the
    #    file, perfectly readable, and are simply never reached. A closing
    #    `exit 0` has nothing after it and so disables nothing.
    idx=$(printf '%s\n' "$body" | head -15 | grep -nE '^exit[[:space:]]+0[[:space:]]*(#.*)?$' | head -1 | cut -d: -f1)
    [[ -n "$idx" ]] || return 1
    (( idx < n_body ))
}

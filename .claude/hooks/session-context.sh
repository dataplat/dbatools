#!/bin/bash
# session-context.sh - Re-inject critical project rules after compaction, resume, or startup.
# Fires on SessionStart. Output goes to stdout and is added to Claude's context.
#
# NOTE: every other script under migration/.claude/hooks/ is an exit-0 stub (see _STUB-NOTE.md).
# This one is real.

cat << 'CONTEXT'
CRITICAL PROJECT RULES (re-injected on session start / compaction / resume):

0. SCOPE GUARD (overrides everything below): work ONLY on what the user's most recent message
   asked for, or on the current GitHub issue. Uncommitted files in git status that you did not
   write in THIS session belong to another session or a paused run — do NOT review, fix,
   integrate, or complete them unless asked. A leftover agent was found mid-run on 2026-07-21;
   assume that can happen again.

1. EVIDENCE IS A LEAD, NOT A FINDING. Tracker Evidence cells in migration/trackers/*.md have been
   caught describing code that does not exist — four confirmed cases. ALWAYS read the actual
   source (.ps1) and the actual port (.cs) before acting on a row. When evidence and code
   disagree, THE CODE WINS and the evidence cell gets corrected. Verify BEFORE you publish a
   claim, not after.

2. THREE REPOS. Coordination + issue queue: potatoqualitee/migration (this repo). PowerShell +
   Pester: ../dbatools (dataplat, PUBLIC). C# + MSTest: ../dbatools.library (dataplat, PUBLIC).
   Both code repos are on branch libmigration.

3. ALWAYS PASS -R potatoqualitee/migration to every gh issue command. gh infers the repo from the
   working directory, so an unpinned command run from a code repo hits the PUBLIC dataplat
   upstream, which shares the same issue number space.

4. THE WORK QUEUE IS GITHUB ISSUES, not trackers/*.md. The lane/coordinator convention
   (/bot, /coordinator, COORDINATION.md, PORTED-AWAITING-GATE queueing) is RETIRED — the operator
   ended it because it burned tokens without converging. Do not revive it.

5. GATE: pwsh.exe -NoProfile -File C:\github\dbatools\migration\tools\Invoke-GateWithWorkstationSteps.ps1 -Command <Cmd> -Module <satellite>
   PASS = all 7 core steps green. SKIPPED NEVER COUNTS AS PASS. A green gate that did not
   exercise the distinguishing leg proves nothing — that is how several rows reached DONE while
   still carrying defects. Cross-record bugs need a MULTI-RECORD piped leg; -WhatIf needs an
   assertion that the side effect did NOT happen.

6. BUILD CONCURRENCY: the gate runs dotnet build on dbatools.sln. NEVER edit dbatools.library
   source while a gate or gate batch is running — the builds pick up half-applied state and the
   verdicts become meaningless.

7. STALE BINARIES: the gate builds on the HOST but measures binaries on the workstation GUEST.
   Ship-Satellite.ps1 is a SEPARATE step. If you skip it you are gating yesterday's DLLs.

8. LAB: dedicated to this migration; destructive operations are PRE-AUTHORIZED (restart services,
   drop endpoints, reset fixtures, revert checkpoints, start VMs). If one SQL instance is offline,
   route to another — never mark BLOCKED(lab) because a single host is down. Reproduce gate
   failures on sql01 (InstanceSingle), NOT on a lane partition like sql02: they carry different
   fixtures and sql02 will look clean.

9. PUSHING IS ALLOWED — the operator owns all three repos (confirmed 2026-07-21). Push ONLY to
   libmigration branches (libmigration, libmigration-<lane>). NEVER push to main / master /
   development on the public dataplat repos, and never force-push anywhere.

10. LINE ENDINGS: migration is normalized to LF and must stay that way (CRLF silently broke a
    tracker append whose regex used an EOL anchor). Do NOT renormalize ../dbatools or
    ../dbatools.library — they are public repos where that would conflict with upstream.

11. VERIFY YOUR WRITES. Tracker edits have silently no-op'd before and exited 0. After editing a
    tracker row, read it back and confirm the change landed.
CONTEXT

---
name: issue
description: Work a GitHub issue end to end — verify the report against development, find every command with the same defect, then fix, test and open a pull request. Also handles triage-only issues that need a comment instead of code.
argument-hint: "<issue number> [optional: triage — investigate and comment, do not write code]"
---

# Work a dbatools Issue

Take a GitHub issue from "please have a look" to either a pull request or an informed comment.

The two failure modes this skill exists to prevent: **fixing something that `development` already fixed**, and **fixing one command when the same defect sits in three**. Steps 2 and 4 are the ones that earn their keep — do not skip them because the fix looks obvious.

## 1. Read the whole issue

```
gh issue view <number> --comments
```

Also check whether someone is already on it:

```
gh pr list --state open --search "<number>"
git branch -a --list "*<keyword>*"
```

If a PR already references the issue, stop and report that instead of duplicating the work.

Note what the reporter offered. dbatools reporters frequently say "I can submit a pull request" — that changes the recommendation at the end, it does not stop you from investigating.

## 2. Verify the report against `development`

Reporters cite the version they run, which is usually behind. Before diagnosing anything, confirm the defect still exists in the current code:

- Read the actual lines in `public/` or `private/`, not the version in the issue text
- `git log -S"<the suspect code>" --oneline -5 -- <file>` shows whether it was already touched
- If it is already fixed, say so with the commit and the version it shipped in, and propose closing the issue

Take the reporter's analysis seriously — it is often correct and specific — but confirm it in the code yourself before acting on it.

### Check the dependency versions too, not just the dbatools version

For anything touching connections, SMO, authentication, encryption or bulk copy, the module version is the *less* interesting number. The behaviour usually comes from `dbatools.library` and the `Microsoft.Data.SqlClient` it ships, and a report is frequently against a library that is months old.

```powershell
# what the repo currently requires
Get-Content .github/dbatools-library-version.json

# what the reporter would get today, and which SqlClient it carries
$lib = (Get-Module dbatools.library -ListAvailable | Select-Object -First 1).ModuleBase
Get-ChildItem -Path $lib -Recurse -Filter "Microsoft.Data.SqlClient.dll" |
    Select-Object -First 1 -ExpandProperty VersionInfo | Select-Object ProductVersion
```

The issue template asks for both the `dbatools.library` and `Microsoft.Data.SqlClient` versions - use them. If the reporter is behind, "update the library" is a real diagnostic step, not a brush-off, and it belongs before any theorising about runtime internals.

The same files answer questions about *how* the stack behaves, which is often faster and more reliable than reasoning about .NET from memory. `dbatools.library` ships native `Microsoft.Data.SqlClient.SNI.dll` under both `core\` and `desktop\`, for instance, so on Windows the client uses native SSPI on PowerShell 7 exactly as it does on 5.1. Claims about managed-versus-native runtime behaviour are checkable against the shipped files - check them, because a confident wrong mechanism sends a thread chasing workarounds that cannot possibly help.

## 3. State the diagnosis before editing

Report to the user: the exact file and line, the mechanism, and the observable symptom. Use `file.ps1:42` references so they are clickable.

## 4. Sweep for the same defect in sibling commands

**This is the step that turns a one-line fix into a real one.** An issue names the command the reporter happened to run; the same pattern usually lives in the neighbouring commands that share the mechanism.

- `grep` the suspect pattern across `public/` and `private/` — the API call, the parameter that is missing, the property that is read
- dbatools command families move together: `Get-`/`Set-`/`Test-`/`Remove-` of the same noun, and anything sharing a scriptblock that runs remotely
- For each hit decide explicitly whether it is the same defect or a deliberate difference, and say which

Then propose the scope to the user and let them choose. Scope is the maintainer's call, not yours — but bring a recommendation, not an open question.

## 5. Branch

Always branch from the tip of `development`, never from whatever is currently checked out:

```
git fetch origin development
git checkout -b <short-kebab-description> origin/development
```

## 6. Fix

Follow the repository-wide PowerShell style and workflow conventions in root `CLAUDE.md`. Update that file rather than copying its rules into this workflow.

## 7. Test

Read `tests/CLAUDE.md` first — the ongoing Pester 6 test policy and `$TestConfig` instance fixture table are there.

Apply its regression and real-boundary coverage requirements. Update that guide rather than copying test policy into this workflow.

Verify at minimum that every changed file parses:

```powershell
[System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
```

Run the real tests through the project's test harness when the fixture is available - see [Reproduce it before theorising about it](#reproduce-it-before-theorising-about-it) for the lab and how to leave it clean. Never hand-roll an `Invoke-Pester` call.

## 8. Quality gates

Run [/precommit](../precommit/SKILL.md) for the style scan, registration check, TODO sweep and codex review of the working diff.

## 9. Commit

The commit message **must** carry the `(do ...)` CI targeting pattern — a hook enforces this:

```
<Command> - <what changed, imperative>

<why, and what deliberately stayed the same>

Fixes #<number>

(do *Pattern*)
```

Choose the narrowest wildcard that covers every touched command.

## 10. Pull request

```
gh pr create --base development --head <branch> --title "..." --body "..."
```

- Base is **always** `development`
- **No `(do ...)` in the title** — CI derives tests from the changed files on a PR, so the marker only makes the title unreadable
- Body: problem, mechanism, what changed, what deliberately did *not* change, how it is tested
- Credit the reporter by `@handle` when their analysis contributed

## 11. Stop

**Never merge, and never offer to.** Merging into `development` is Chrissy's call after review. Report the PR URL and stop.

## Triage-only mode

When the issue is a question, a support request, or user error, the deliverable is a comment, not a branch. Investigate with the same rigour — steps 1, 2 and 4 — then draft the comment and **show it to the user for approval before posting**. Do not post to a public issue tracker unprompted.

Connection and environment reports usually turn on a comparison the reporter made: "it works here but not there". Check how many variables that comparison changes at once. A test that works in Windows PowerShell with `System.Data.SqlClient` and fails in PowerShell 7 with `Microsoft.Data.SqlClient` has changed both the host and the client library, and proves nothing about either. The most useful thing a comment can offer is usually not another workaround but **the one experiment that isolates a single variable** - it either sends the issue upstream cleanly or brings it back with evidence worth acting on.

Read the whole thread before adding to it, including earlier bot analyses. If a previous answer asserted a mechanism that turns out to be wrong, say so plainly and correct it. Workarounds derived from a wrong mechanism cannot work, and a reporter who has already tried three of them has earned a straight answer rather than a fourth.

### Reproduce it before theorising about it

**Check for a lab first.** If `C:\GitHub\testing-dbatools` exists, read its `CLAUDE.md`: it describes a live multi-instance lab and the harness that drives it. Reproducing the reporter's exact steps against a real instance beats any amount of static analysis, and it is what turns "someone should test this" into a closed issue in a single pass.

```powershell
# one PowerShell call - session state does not persist between tool invocations,
# so dot-sourcing and the repro have to happen together
Set-Location -Path "C:\GitHub\testing-dbatools"
. .\Initialize-LabSession.ps1     # imports dbatools from source, loads $TestConfig
```

Rules for touching the lab:

- **Reproduce on the version the reporter used** when the instances allow it, and on the current one, so "fixed" versus "never reproduced here" can be told apart
- **Clean up in a `finally`.** `TestEnvironment.Tests.ps1` asserts the lab is pristine - no user databases, no leftover logins or endpoints - and the next test run fails if it is not. Name objects `dbatoolsci_*` and drop them, then confirm nothing is left
- **Assert the data, not just the row count.** A copy that reports success while writing corrupt values is a different bug, not a fix
- `Reset-TestEnvironment.ps1 -WhatIf` first if a run dies halfway through, since the real thing drops databases
- The lab is real infrastructure someone pays for. Reproduce the issue, then stop; do not go exploring

The lab is built from two public repositories - [testing-dbatools](https://github.com/andreasjordan/testing-dbatools) for the harness and [MyAzureLab](https://github.com/andreasjordan/MyAzureLab) for the environment (see [HyperVLab](https://github.com/andreasjordan/MyAzureLab/tree/main/HyperVLab) for the current multi-machine setup). It is mainly used by Andreas Jordan (@andreasjordan), so treat it as his machine: it is not a shared resource that any contributor can be assumed to have, and an issue must never be closed on the basis that "it works in the lab" without saying which versions were tested.

## Output

Finish with: what the defect was, which files changed and why, what was deliberately left alone, test status (run / not run and why), and the PR URL.

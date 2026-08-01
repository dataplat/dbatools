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

Follow `CLAUDE.md`. The rules that matter most in bug-fix diffs:

- No backticks; splat at 3+ parameters with `$splat<Purpose>` naming
- No `= $true` in parameter attributes, no `::new()` (PowerShell v3 support)
- Double quotes, aligned hashtables, every existing comment preserved
- Add a short comment saying **why** the fix is needed. A bare `-Force` or an extra `-not` reads as noise to the next maintainer; one line explaining the failure mode does not.

## 7. Test

Read `tests/CLAUDE.md` first — Pester v5 block rules and the `$TestConfig` instance fixture table are there.

Add 1-3 focused tests that fail without the fix. For a bug fix specifically:

- Prefer extending an existing test file that already builds the fixture you need over standing up a new one
- Pick the **lightest** `$TestConfig` instance that can show the bug; the fixture decides which AppVeyor scenario the test lands in
- If the test mutates machine state (certificates, services, registry), restore it in a `try`/`finally` inside the `It`, because `AfterAll` cleanup may not be able to undo it
- If the defect only reproduces on a fixture the CI does not have, say so plainly rather than writing a test that cannot fail

Verify at minimum that every changed file parses:

```powershell
[System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
```

Run the real tests through the project's test harness when the fixture is available. Never hand-roll an `Invoke-Pester` call.

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

## Output

Finish with: what the defect was, which files changed and why, what was deliberately left alone, test status (run / not run and why), and the PR URL.

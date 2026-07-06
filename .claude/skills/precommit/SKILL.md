---
name: precommit
description: Run every dbatools quality gate on demand before committing — style scan, command registration, TODO sweep, and a codex review of the working diff.
argument-hint: "[optional: file paths to limit the check]"
---

# Precommit Quality Sweep

Run the same gates the Stop hooks enforce, but on demand and against the full working diff (including changes made via Bash, which the session-scoped auto-review can't see). Report a single pass/fail summary at the end.

## Gates, in order

### 1. Style scan (changed PowerShell files)

For each changed `*.ps1` (from `git diff --name-only HEAD` + untracked), check the dbatools style rules from CLAUDE.md: no backticks for line continuation, no `= $true` in parameter attributes, no `::new()`, double quotes not single quotes, `$splat<Purpose>` naming, no ArrayList/List collection, hashtable `=` alignment, no trailing whitespace. Report violations as `path:line — rule`.

### 2. Registration check (new commands)

For each new `public/*.ps1`, confirm the function name appears in `dbatools.psd1` (FunctionsToExport) AND `dbatools.psm1`. 

### 3. TODO sweep

`grep -n -i -E '\b(TODO|FIXME|HACK|XXX|WORKAROUND)\b'` across changed code files (exclude `.claude/`). Each hit must be resolved or explicitly acknowledged by the user.

### 4. Codex review (if codex is installed)

Invoke the [/codex](../codex/SKILL.md) skill with `uncommitted` scope. Skip with a note if codex is not installed.

### 5. Commit message reminder

Remind that the commit message must include the `(do <CommandName>)` CI targeting pattern.

## Output

Finish with a table: gate | result (PASS / FAIL / SKIPPED-why) | details. If everything passes, say the changes are ready to commit.

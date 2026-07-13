# Issue #9600 Agent-Job Wildcards and Pattern Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing wildcard contract explicit and add regular-expression job-name matching through a new `Pattern` parameter.

**Architecture:** Simplify `Get-JobList` to the `-Like`/`-NotLike` behavior it already executes for every job and step filter. Mark `JobName` and `StepName` as wildcard-capable. In `Find-DbaAgentJob`, retrieve jobs using the current JobName/StepName precedence, then apply one-or-more regex patterns as an additional narrowing filter before the existing category/status/owner filters. Keep `ExcludeJobName` exact.

**Tech Stack:** PowerShell 3-compatible dbatools functions, PowerShell wildcard engine, .NET regex via `-match`, Pester 5 mocks, git worktrees, GitHub CLI/app, Claude CLI.

## Global Constraints

- Work only in `.worktrees/issue-9600-agent-job-pattern` on branch `codex/issue-9600-agent-job-pattern`, based on current `origin/development`.
- Reconfirm issue #9600 remains open, unassigned, maintainer-approved, and free of overlapping pull requests before editing and publication.
- Preserve effective wildcard behavior, including `?`, character classes, and `[WildcardPattern]::Escape()` output. Do not invent malformed-pattern validation.
- `Pattern` is a regular expression matched against job names. Multiple patterns use OR semantics and each job is emitted once.
- `Pattern` narrows the jobs selected by existing `JobName`/`StepName`; it does not change their current precedence. `ExcludeJobName` remains exact.
- Update parameter validation and wildcard metadata tests whenever the public parameter block changes.
- Commit messages must include `(do Find-DbaAgentJob)`.
- Publish one draft pull request that links and closes only issue #9600.

---

## Task 1: Prepare the isolated issue branch

**Files:**

- Read: `CLAUDE.md`
- Read: `tests/CLAUDE.md`
- Read: `.github/prompts/migration.md`
- Read: `.github/prompts/style.md`

- [ ] Refresh issue/PR state, verify `.worktrees` is ignored, and create the branch:

```powershell
git fetch origin development
gh issue view 9600 --repo dataplat/dbatools --json number,state,assignees,labels,title,url
gh pr list --repo dataplat/dbatools --state open --search "9600 in:title,body" --json number,title,headRefName,url
git check-ignore .worktrees
git worktree add .worktrees/issue-9600-agent-job-pattern -b codex/issue-9600-agent-job-pattern origin/development
git -C .worktrees/issue-9600-agent-job-pattern status --short --branch
```

## Task 2: Lock down wildcard and exact-exclusion behavior

**Files:**

- Modify: `tests/Find-DbaAgentJob.Tests.ps1`
- Modify: `private/functions/Get-JobList.ps1:74-117`

**Interfaces:**

- `Get-JobList -JobFilter` and `-StepFilter` use PowerShell wildcard syntax for every supplied string.
- `Get-JobList -Not` retains its current `-NotLike` behavior.
- `Find-DbaAgentJob -ExcludeJobName` remains an exact `-notcontains` filter.

- [ ] Add deterministic mocked jobs to a unit `InModuleScope dbatools` context:

```powershell
Context "Wildcard filtering" {
    InModuleScope dbatools {
        BeforeAll {
            $script:agentJobs = @(
                [PSCustomObject]@{ Name = "Backup1Nightly"; JobSteps = @([PSCustomObject]@{ Name = "LoadData" }) }
                [PSCustomObject]@{ Name = "Backup2Nightly"; JobSteps = @([PSCustomObject]@{ Name = "LoadMeta" }) }
                [PSCustomObject]@{ Name = "ETL1"; JobSteps = @([PSCustomObject]@{ Name = "Extract" }) }
                [PSCustomObject]@{ Name = "ETL2"; JobSteps = @([PSCustomObject]@{ Name = "LoadData" }) }
                [PSCustomObject]@{ Name = "Literal*Job"; JobSteps = @([PSCustomObject]@{ Name = "Literal*Step" }) }
                [PSCustomObject]@{ Name = "LiteralXJob"; JobSteps = @([PSCustomObject]@{ Name = "LiteralXStep" }) }
            )
            $script:agentServer = [PSCustomObject]@{
                ComputerName       = "sql1"
                ServiceName        = "MSSQLSERVER"
                DomainInstanceName = "sql1"
                JobServer          = [PSCustomObject]@{ Jobs = $script:agentJobs }
            }
            Mock Connect-DbaInstance { $script:agentServer }
        }

        It "supports question-mark and character-class job wildcards" {
            (Get-JobList -SqlInstance "sql1" -JobFilter "Backup?Nightly").Name | Should -Be @("Backup1Nightly", "Backup2Nightly")
            (Get-JobList -SqlInstance "sql1" -JobFilter "ETL[12]").Name | Should -Be @("ETL1", "ETL2")
        }

        It "supports escaped literal asterisks and step wildcards" {
            $escapedJobName = [WildcardPattern]::Escape("Literal*Job")
            (Get-JobList -SqlInstance "sql1" -JobFilter $escapedJobName).Name | Should -Be "Literal*Job"
            (Get-JobList -SqlInstance "sql1" -StepFilter "Load?ata").Name | Should -Be @("Backup1Nightly", "ETL2")
        }
    }
}
```

- [ ] Run the focused unit tests. The new wildcard assertions should describe current effective behavior and pass before the refactor; this is the characterization step that prevents the dead-branch cleanup from changing behavior:

```powershell
Invoke-ManualPester -Path tests/Find-DbaAgentJob.Tests.ps1 -Show Detailed -PassThru
```

- [ ] Remove the `$jFilter -match '`*'` and `$sFilter -match '`*'` branches. Keep only the currently effective `-Like`/`-NotLike` operations, including existing multi-filter emission behavior:

```powershell
foreach ($jFilter in $JobFilter) {
    if ($Not) {
        $job | Where-Object Name -NotLike $jFilter
    } else {
        $job | Where-Object Name -Like $jFilter
    }
}
foreach ($sFilter in $StepFilter) {
    if ($Not) {
        $stepFound = $job.JobSteps | Where-Object Name -NotLike $sFilter
    } else {
        $stepFound = $job.JobSteps | Where-Object Name -Like $sFilter
    }
    if ($stepFound.Count -gt 0) {
        $job
    }
}
```

- [ ] Re-run the characterization tests and confirm identical results:

```powershell
Invoke-ManualPester -Path tests/Find-DbaAgentJob.Tests.ps1 -Show Detailed -PassThru
```

## Task 3: Add regex Pattern and wildcard metadata test-first

**Files:**

- Modify: `public/Find-DbaAgentJob.ps1`
- Modify: `tests/Find-DbaAgentJob.Tests.ps1`

- [ ] Add `Pattern` to the expected parameter list immediately after `StepName`, then add unit assertions for wildcard metadata, regex OR semantics, combination with JobName, and exact exclusion. Mock `Get-JobList` to return `$script:agentJobs` and `Select-DefaultView` to pass through its input:

```powershell
Context "Public name filters" {
    InModuleScope dbatools {
        BeforeEach {
            Mock Connect-DbaInstance { $script:agentServer }
            Mock Get-JobList { $script:agentJobs }
            Mock Select-DefaultView { $InputObject }
        }

        It "marks JobName and StepName as wildcard-capable" {
            $command = Get-Command Find-DbaAgentJob

            @($command.Parameters["JobName"].Attributes | Where-Object { $PSItem -is [SupportsWildcardsAttribute] }) | Should -HaveCount 1
            @($command.Parameters["StepName"].Attributes | Where-Object { $PSItem -is [SupportsWildcardsAttribute] }) | Should -HaveCount 1
        }

        It "matches job names with regex Pattern OR semantics" {
            $results = Find-DbaAgentJob -SqlInstance "sql1" -Pattern "^Backup\dNightly$", "^ETL2$"

            $results.Name | Should -Be @("Backup1Nightly", "Backup2Nightly", "ETL2")
        }

        It "narrows JobName results by Pattern and keeps ExcludeJobName exact" {
            Mock Get-JobList { $script:agentJobs | Where-Object Name -Like "Literal*" }

            $results = Find-DbaAgentJob -SqlInstance "sql1" -JobName "Literal*" -Pattern "^Literal.*Job$" -ExcludeJobName "Literal*Job"

            $results.Name | Should -Be "LiteralXJob"
        }
    }
}
```

- [ ] Run the focused tests and confirm failure because `Pattern` and wildcard metadata do not exist:

```powershell
Invoke-ManualPester -Path tests/Find-DbaAgentJob.Tests.ps1 -Show Detailed -PassThru
```

- [ ] Add help for the regex parameter and one example:

```text
    .PARAMETER Pattern
        Filters job names using one or more regular expressions. Multiple patterns use OR semantics.
        Combine this with JobName or StepName to further narrow those results.
```

```text
    .EXAMPLE
        PS C:\> Find-DbaAgentJob -SqlInstance Dev01 -Pattern "^(Backup|Restore)-\d{4}$"

        Returns jobs whose names match the supplied regular expression.
```

- [ ] Mark only `JobName` and `StepName` with `[SupportsWildcards()]`, add `[string[]]$Pattern` after `StepName`, and include `[boolean]$Pattern` in the begin-block search-term validation.

- [ ] After the current JobName/StepName/all-jobs retrieval has assigned `$jobs`, narrow it with regex OR semantics and update `$output`:

```powershell
if ($Pattern) {
    Write-Message -Level Verbose -Message "Filtering job names by regular expression pattern."
    $jobs = foreach ($job in $jobs) {
        foreach ($regexPattern in $Pattern) {
            if ($job.Name -match $regexPattern) {
                $job
                break
            }
        }
    }
    $output = $jobs
}
```

- [ ] Keep the existing `if (-not ($JobName -or $StepName))` retrieval condition so Pattern-only calls first retrieve all jobs. Leave `ExcludeJobName` as `$ExcludeJobName -notcontains $PSItem.Name`.

- [ ] Re-run focused tests and ScriptAnalyzer:

```powershell
Invoke-ManualPester -Path tests/Find-DbaAgentJob.Tests.ps1 -ScriptAnalyzer -Show Detailed -PassThru
```

- [ ] If a configured SQL test instance is available, run the existing integration tests as a compatibility check:

```powershell
Invoke-ManualPester -Path tests/Find-DbaAgentJob.Tests.ps1 -TestIntegration -Show Detailed -PassThru
```

- [ ] Inspect and commit the full change:

```powershell
git diff --check
git diff -- private/functions/Get-JobList.ps1 public/Find-DbaAgentJob.ps1 tests/Find-DbaAgentJob.Tests.ps1
git add private/functions/Get-JobList.ps1 public/Find-DbaAgentJob.ps1 tests/Find-DbaAgentJob.Tests.ps1
git commit -m "Add regex agent-job name filtering (do Find-DbaAgentJob)"
```

## Task 4: Verify, review, and publish the draft PR

- [ ] Rebase on latest `origin/development`; rerun unit tests, ScriptAnalyzer, and available integration tests; require clean status and `git diff --check`.

- [ ] Run the nonce-fenced read-only Claude review with `claude -p --model opus --effort high --tools Read --permission-mode dontAsk --no-session-persistence --output-format text`, following `.claude/skills/codex/SKILL.md` priorities and requiring an exact final verdict line.

- [ ] Resolve every valid finding test-first and repeat with prior findings in a new nonce fence until Claude returns `VERDICT: CLEAN`.

- [ ] Reconfirm issue/PR state, push `codex/issue-9600-agent-job-pattern`, and create one draft PR titled `Add regex Pattern filtering to Find-DbaAgentJob`. Its body must contain `Closes #9600`, describe wildcard compatibility and exact exclusion, list exact test results and Claude verdict, and allow maintainer edits:

```powershell
gh issue view 9600 --repo dataplat/dbatools --json state,assignees,labels
gh pr list --repo dataplat/dbatools --state open --search "9600 in:title,body" --json number,title,url
git push -u origin codex/issue-9600-agent-job-pattern
```

- [ ] Verify the remote PR is draft, targets `development`, uses the intended head, changes only the private helper, public command, and test, and has initial checks running.

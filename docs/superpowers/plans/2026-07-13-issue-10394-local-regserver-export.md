# Issue #10394 Local Registered-Server Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export native local `RegisteredServer` and `ServerGroup` objects without a null `SqlInstance` failure and without filename collisions.

**Architecture:** Resolve a filename source prefix only when the caller did not supply a single explicit `FilePath`. Preserve nonempty `SqlInstance` for central-management objects, use native `ServerName` for local registered servers, and use source/parent metadata plus the full native group ancestry for local groups. Sanitize backslashes with the existing `$` replacement and leave single explicit paths untouched.

**Tech Stack:** PowerShell 3-compatible dbatools functions, SMO RegisteredServers objects, Pester 5 with TestDrive, git worktrees, GitHub CLI/app, Claude CLI.

## Global Constraints

- Work only in `.worktrees/issue-10394-local-regserver-export` on branch `codex/issue-10394-local-regserver-export`, created from current `origin/development`.
- Reconfirm issue #10394 is open, unassigned, and has no overlapping pull request before editing and publication.
- Preserve central-management filename prefixes and the exact caller-supplied path when one input object uses `FilePath`.
- Use native SMO objects in tests; do not depend on a developer's SSMS local-store file or a live SQL Server.
- Use `New-Object`, not `::new()`, and retain PowerShell 3 compatibility.
- Commit messages must include `(do Export-DbaRegServer)`.
- Publish one draft pull request that links and closes only issue #10394.

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
gh issue view 10394 --repo dataplat/dbatools --json number,state,assignees,labels,title,url
gh pr list --repo dataplat/dbatools --state open --search "10394 in:title,body" --json number,title,headRefName,url
git check-ignore .worktrees
git worktree add .worktrees/issue-10394-local-regserver-export -b codex/issue-10394-local-regserver-export origin/development
git -C .worktrees/issue-10394-local-regserver-export status --short --branch
```

## Task 2: Add deterministic native-object export regressions

**Files:**

- Modify: `tests/Export-DbaRegServer.Tests.ps1`

**Interfaces:**

- Native `RegisteredServer.SqlInstance` and `ServerGroup.SqlInstance` can be null.
- Native `RegisteredServer.ServerName` is the local server identity.
- Native `ServerGroup.Parent` supplies an ancestry chain ending at `DatabaseEngineServerGroup`.
- `RegisteredServer.Export()` and `ServerGroup.Export()` can write deterministic test XML without a live SQL instance.

- [ ] Add a unit context using a default native store, two parent groups with the same child-group name, a local registered server, and a central-like registered server decorated with `SqlInstance`:

```powershell
Context "Native local registered-server exports" {
    BeforeAll {
        $nativeStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore
        $nativeRoot = $nativeStore.DatabaseEngineServerGroup
        $parentA = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($nativeRoot, "ParentA")
        $parentB = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($nativeRoot, "ParentB")
        $sharedGroupA = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($parentA, "Shared")
        $sharedGroupB = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($parentB, "Shared")
        $localServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($sharedGroupA, "LocalAlias")
        $localServer.ServerName = "localhost\SQLEXPRESS"
        $centralServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($sharedGroupA, "CentralAlias")
        $centralServer.ServerName = "application-sql"
        $centralServer | Add-Member -Name SqlInstance -MemberType NoteProperty -Value "cms\prod" -Force
        $script:regServerExportFiles = @()
    }

    AfterAll {
        $script:regServerExportFiles | Remove-Item -ErrorAction SilentlyContinue
    }

    It "exports a local RegisteredServer with a generated name and preserves an explicit FilePath" {
        $generatedFile = $localServer | Export-DbaRegServer -Path $TestDrive -EnableException
        $explicitPath = Join-Path $TestDrive "explicit-local.xml"
        $explicitFile = $localServer | Export-DbaRegServer -FilePath $explicitPath -EnableException
        $script:regServerExportFiles += $generatedFile, $explicitFile

        $generatedFile.Name | Should -BeLike "localhost`$SQLEXPRESS-regserver-LocalAlias-*.xml"
        $explicitFile.FullName | Should -Be $explicitPath
    }

    It "uses the existing SqlInstance prefix for a central registered server" {
        $centralFile = $centralServer | Export-DbaRegServer -Path $TestDrive -EnableException
        $script:regServerExportFiles += $centralFile

        $centralFile.Name | Should -BeLike "cms`$prod-regserver-CentralAlias-*.xml"
    }

    It "exports same-named local groups to collision-free generated and explicit paths" {
        $generatedFiles = @($sharedGroupA, $sharedGroupB) | Export-DbaRegServer -Path $TestDrive -EnableException
        $explicitBase = Join-Path $TestDrive "groups.xml"
        $explicitFiles = @($sharedGroupA, $sharedGroupB) | Export-DbaRegServer -FilePath $explicitBase -EnableException
        $script:regServerExportFiles += $generatedFiles
        $script:regServerExportFiles += $explicitFiles

        $generatedFiles | Should -HaveCount 2
        $generatedFiles.FullName | Select-Object -Unique | Should -HaveCount 2
        $explicitFiles | Should -HaveCount 2
        $explicitFiles.FullName | Select-Object -Unique | Should -HaveCount 2
        $generatedFiles.Name -join "," | Should -BeLike "*ParentA`$Shared*"
        $generatedFiles.Name -join "," | Should -BeLike "*ParentB`$Shared*"
    }
}
```

- [ ] Run the focused unit tests and confirm generated local server/group exports fail at `$object.SqlInstance.Replace()` and same-leaf explicit group paths collide:

```powershell
Invoke-ManualPester -Path tests/Export-DbaRegServer.Tests.ps1 -Show Detailed -PassThru
```

## Task 3: Resolve a safe, stable export identity

**Files:**

- Modify: `public/Export-DbaRegServer.ps1:172-193`

- [ ] Immediately after `$regname` initialization, resolve the source identity without calling a method on a null property. For local groups, replace the leaf-only registration name with the complete parent path so two `Shared` groups cannot collide:

```powershell
$regname = $object.Name.Replace("\", "$")
$sourceName = [string]$object.SqlInstance

if ([string]::IsNullOrWhiteSpace($sourceName)) {
    if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {
        $sourceName = [string]$object.ServerName
    } else {
        $groupNames = @($object.Name)
        $parentGroup = $object.Parent
        while ($null -ne $parentGroup -and $parentGroup.Name -ne "DatabaseEngineServerGroup") {
            $groupNames = @($parentGroup.Name) + $groupNames
            $parentGroup = $parentGroup.Parent
        }
        $regname = ($groupNames -join "\").Replace("\", "$")
        $sourceName = [string]$object.Source
        if ([string]::IsNullOrWhiteSpace($sourceName)) {
            $sourceName = [string]$object.ParentServer
        }
    }
}

if ([string]::IsNullOrWhiteSpace($sourceName)) {
    $sourceName = [string]$object.Source
}
if ([string]::IsNullOrWhiteSpace($sourceName)) {
    $sourceName = "Local"
}
```

- [ ] In the generated-filename branch, sanitize the already-resolved identity instead of reading `SqlInstance` again:

```powershell
$serverName = $sourceName.Replace("\", "$")
```

- [ ] Preserve the existing filename shapes, `$timeNow`, `Join-DbaPath`, single explicit path, multi-object suffixing, export call, and error handling.

- [ ] Run unit tests, ScriptAnalyzer, and diff checks:

```powershell
Invoke-ManualPester -Path tests/Export-DbaRegServer.Tests.ps1 -ScriptAnalyzer -Show Detailed -PassThru
git diff --check
git diff -- public/Export-DbaRegServer.ps1 tests/Export-DbaRegServer.Tests.ps1
```

- [ ] When a configured SQL test instance is available, also run the existing integration coverage to prove CMS behavior remains intact:

```powershell
Invoke-ManualPester -Path tests/Export-DbaRegServer.Tests.ps1 -TestIntegration -Show Detailed -PassThru
```

- [ ] Commit the tested change:

```powershell
git add public/Export-DbaRegServer.ps1 tests/Export-DbaRegServer.Tests.ps1
git commit -m "Support local registered-server exports (do Export-DbaRegServer)"
```

## Task 4: Verify, review, and publish the draft PR

- [ ] Rebase on latest `origin/development`, rerun unit/ScriptAnalyzer and available integration tests, require `git diff --check` and a clean worktree.

- [ ] Run the nonce-fenced read-only Claude review with `claude -p --model opus --effort high --tools Read --permission-mode dontAsk --no-session-persistence --output-format text`, following `.claude/skills/codex/SKILL.md` priorities and requiring an exact `VERDICT: CLEAN` or `VERDICT: CHANGES_REQUESTED` final line.

- [ ] Resolve valid findings test-first and repeat with prior-round findings in a fresh nonce fence until Claude returns `VERDICT: CLEAN`.

- [ ] Reconfirm issue/PR state, push `codex/issue-10394-local-regserver-export`, and create one draft PR titled `Support exporting local registered servers`. The body must contain `Closes #10394`, explain the identity fallback order and collision handling, list exact test results and Claude verdict, and allow maintainer edits:

```powershell
gh issue view 10394 --repo dataplat/dbatools --json state,assignees,labels
gh pr list --repo dataplat/dbatools --state open --search "10394 in:title,body" --json number,title,url
git push -u origin codex/issue-10394-local-regserver-export
```

- [ ] Verify the remote PR is draft, targets `development`, uses the intended head, changes only the command and its test, and has initial checks running.

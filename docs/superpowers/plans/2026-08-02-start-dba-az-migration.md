# Start-DbaAzMigration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a public, database-only `Start-DbaAzMigration` command that moves selected SQL Server databases into an existing Azure SQL logical server through BACPAC export/import, with safe replacement, cleanup, standard migration output, and a non-skipping real Azure integration test.

**Architecture:** Implement a thin public orchestrator over the existing DacFx-backed `Export-DbaDacPackage` and `Publish-DbaDacPackage` commands. Connect once to each endpoint, validate the Azure SQL Database boundary before mutation, process databases sequentially, and isolate friendly-mode failures per database. Do not add an installer, module dependency, Azure control-plane runtime dependency, or server-object migration.

**Tech Stack:** PowerShell 3+, dbatools, Microsoft DacFx from `dbatools.library`, Pester 6, Azure SQL Database, Azure CLI for local test provisioning only.

## Global Constraints

- Follow `CLAUDE.md` and `tests/CLAUDE.md` for every PowerShell and test change.
- Work only in `C:\github\dbatools\.worktrees\start-dba-az-migration` on `codex/start-dba-az-migration`.
- Use red-green-refactor: observe every new behavioral test fail for the expected missing or incorrect behavior before production code is added.
- Use no mocks as substitutes for real behavior. Focused validation/unit tests may supplement, but the Azure migration scenario must cross real SQL Server, filesystem, DacFx, network, and Azure SQL boundaries.
- Use PowerShell 3-compatible syntax: no `::new()`, no null-coalescing operators, no classes, and no backtick line continuations.
- Use the author string `the dbatools team + Claude` in the new public command.
- Use `(do Start-DbaAzMigration)` in every implementation commit message.
- Never log credentials, passwords, access tokens, or complete connection strings.
- Keep Azure CLI and `Az.*` modules out of the public command. The existing DacFx assembly is the only product dependency.
- Ensure local Azure resources are removed even when verification fails.

---

## Task 1: Lock the public command contract and registration

**Files:**

- Create: `tests/Start-DbaAzMigration.Tests.ps1`
- Create: `public/Start-DbaAzMigration.ps1`
- Modify: `dbatools.psd1`
- Modify: `dbatools.psm1`

- [ ] **Step 1: Add the Pester 6 contract test**

Create `tests/Start-DbaAzMigration.Tests.ps1` with the mandatory header and an exact parameter-surface assertion:

```powershell
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaAzMigration",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "Database",
                "ExcludeDatabase",
                "Path",
                "ExportDacOption",
                "ImportDacOption",
                "Force",
                "KeepBacpac",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
```

- [ ] **Step 2: Prove the contract is red**

Run from the worktree:

```powershell
$global:TestConfig = Get-TestConfig
$configuration = New-PesterConfiguration
$configuration.Run.Path = "tests/Start-DbaAzMigration.Tests.ps1"
$configuration.Run.PassThru = $true
$configuration.Filter.Tag = "UnitTests"
$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -ne 1) { throw "Expected exactly one missing-command failure" }
```

Expected: the test fails because `Start-DbaAzMigration` does not exist.

- [ ] **Step 3: Add the public command shell**

Create `public/Start-DbaAzMigration.ps1` with complete comment-based help, `SupportsShouldProcess`, `ConfirmImpact = "Medium"`, and this parameter block:

```powershell
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
param (
    [Parameter(Mandatory)]
    [DbaInstanceParameter]$Source,
    [Parameter(Mandatory)]
    [DbaInstanceParameter]$Destination,
    [PSCredential]$SourceSqlCredential,
    [PSCredential]$DestinationSqlCredential,
    [object[]]$Database,
    [object[]]$ExcludeDatabase,
    [string]$Path = (Get-DbatoolsConfigValue -FullName "Path.DbatoolsTemp"),
    [object]$ExportDacOption,
    [object]$ImportDacOption,
    [switch]$Force,
    [switch]$KeepBacpac,
    [switch]$EnableException
)
```

The shell may return without action after `Test-FunctionInterrupt`; do not implement migration behavior in this task.

- [ ] **Step 4: Register the command in both module files**

Insert `Start-DbaAzMigration` alphabetically with the other exported commands in:

- `dbatools.psd1` `FunctionsToExport`
- `dbatools.psm1` `$script:xplat`

- [ ] **Step 5: Prove registration is green**

Import `./dbatools.psm1` in a fresh PowerShell process and rerun the Task 1 test. Expected: 1 passed, 0 failed.

- [ ] **Step 6: Commit the contract**

```powershell
git add tests/Start-DbaAzMigration.Tests.ps1 public/Start-DbaAzMigration.ps1 dbatools.psd1 dbatools.psm1
git commit -m "Start-DbaAzMigration - Add public command contract (do Start-DbaAzMigration)"
```

---

## Task 2: Implement validation, selection, orchestration, output, and cleanup

**Files:**

- Modify: `tests/Start-DbaAzMigration.Tests.ps1`
- Modify: `public/Start-DbaAzMigration.ps1`

- [ ] **Step 1: Add real-boundary behavioral coverage**

Add an `IntegrationTests` Describe that uses the configured SQL test instances and filesystem. Cover these behaviors with small uniquely named databases:

1. Rejects a destination whose `DatabaseEngineEdition` is not `SqlDatabase` before exporting.
2. Rejects a non-`DacExportOptions` `ExportDacOption` and a non-`DacImportOptions` `ImportDacOption`.
3. Fails clearly before migration when an explicitly requested source database is missing.
4. Selects all accessible user databases when `Database` is omitted and applies `ExcludeDatabase` after selection.
5. Emits `Skipped` and does not export when the destination database already exists without `Force`.
6. Honors `WhatIf` without exporting a package or changing the destination.
7. Produces one `MigrationObject` with `SourceServer`, `DestinationServer`, `Name`, `DestinationDatabase`, `Type`, `Status`, `Notes`, `DateTime`, `BacpacPath`, and `Elapsed`.
8. Deletes the BACPAC after a successful migration by default.
9. Keeps the BACPAC when `KeepBacpac` is set.
10. Drops and recreates an existing destination database only with `Force`.
11. Continues to the next selected database after an operational failure in friendly mode and stops with a catchable error under `EnableException`.

Where a behavior genuinely requires Azure SQL semantics, keep its executable assertion in Task 3 rather than weakening it with a mock. The local SQL boundary in this task may validate selection, WhatIf, option types, and missing-database behavior; the real Azure boundary owns success, skip, force, cleanup, retention, and end-to-end output.

- [ ] **Step 2: Run each new focused context and observe red**

Run the new test file directly through Pester 6 after importing `./dbatools.psm1`. Expected red reasons must be the unimplemented validation/selection/status behavior, not setup or syntax failures.

- [ ] **Step 3: Implement begin-block validation**

In `Start-DbaAzMigration`:

- Call `Test-ExportDirectory -Path $Path`.
- Reject `ExportDacOption` unless it is `Microsoft.SqlServer.Dac.DacExportOptions`.
- Reject `ImportDacOption` unless it is `Microsoft.SqlServer.Dac.DacImportOptions`.
- Connect to source and destination once using splats and `Connect-DbaInstance`; use destination database context `master`.
- Require destination `DatabaseEngineEdition` to equal the SMO Azure SQL Database value `SqlDatabase`; direct Managed Instance users to `Copy-DbaDatabase`.
- Return immediately after terminating validation in friendly mode, and honor `EnableException` on every `Stop-Function` call.

- [ ] **Step 4: Implement exact source selection**

Enumerate `Get-DbaDatabase -SqlInstance $sourceServer -ExcludeSystem -OnlyAccessible`. Convert `Database` and `ExcludeDatabase` inputs to their string names, apply the allow-list then deny-list, and compare explicit requested names case-insensitively against the accessible set. If any requested name is missing or inaccessible, stop before `ShouldProcess`, export, or destination mutation and list those names in the error.

If no database remains after filtering, stop with an actionable message.

- [ ] **Step 5: Implement per-database status construction**

Use a fresh ordered object for every database:

```powershell
$migrationStatus = [pscustomobject][ordered]@{
    SourceServer       = $sourceServer.Name
    DestinationServer  = $destinationServer.Name
    Name               = $databaseName
    DestinationDatabase = $databaseName
    Type               = "Database"
    Status             = $null
    Notes              = $null
    DateTime           = [DbaDateTime](Get-Date)
    BacpacPath         = $null
    Elapsed            = $null
}
```

Emit through:

```powershell
$migrationStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
```

- [ ] **Step 6: Implement existing-target and ShouldProcess behavior**

Check the destination by exact database name. Without `Force`, emit `Skipped` with `Already exists on destination`. With `Force`, call `ShouldProcess` before `Remove-DbaDatabase -SqlInstance $destinationServer -Database $databaseName -Confirm:$false -EnableException`. Call `ShouldProcess` before the migration itself so `WhatIf` creates no package and performs no import.

- [ ] **Step 7: Implement BACPAC export and import**

Use explicit splats:

```powershell
$exportSplat = @{
    SqlInstance     = $sourceServer
    Database        = $databaseName
    Path            = $Path
    Type            = "Bacpac"
    EnableException = $true
}
if ($ExportDacOption) { $exportSplat.DacOption = $ExportDacOption }
```

Validate that exactly one returned object has an existing `Path`, record that path, then import with:

```powershell
$publishSplat = @{
    ConnectionString = $destinationServer.ConnectionContext.ConnectionString
    Database         = $databaseName
    Path             = $bacpacPath
    Type             = "Bacpac"
    EnableException  = $true
}
if ($ImportDacOption) { $publishSplat.DacOption = $ImportDacOption }
```

Require one publish result. Mark the status `Successful` and include phase-specific notes only when needed.

- [ ] **Step 8: Implement failure isolation and cleanup**

Track whether import began and whether the destination was absent or deliberately removed. On import failure, query for and remove a partial destination database without hiding the original error. In friendly mode emit `Failed` and continue; with `EnableException`, call `Stop-Function` with the original error and stop. In `finally`, remove the BACPAC with `Remove-Item -LiteralPath` unless `KeepBacpac` is set. Record stopwatch elapsed time for every emitted status.

- [ ] **Step 9: Make Task 2 tests green and refactor**

Run the new unit/integration contexts plus existing focused tests:

```powershell
tests/Start-DbaAzMigration.Tests.ps1
tests/Export-DbaDacPackage.Tests.ps1
tests/Publish-DbaDacPackage.Tests.ps1
tests/Start-DbaMigration.Tests.ps1
```

Expected: all runnable focused tests pass; no setup failures are hidden as skips.

- [ ] **Step 10: Commit the orchestrator**

```powershell
git add public/Start-DbaAzMigration.ps1 tests/Start-DbaAzMigration.Tests.ps1
git commit -m "Start-DbaAzMigration - Implement BACPAC orchestration (do Start-DbaAzMigration)"
```

---

## Task 3: Add the required real Azure SQL integration scenario

**Files:**

- Modify: `.github/scripts/gh-actions.ps1`
- Modify: `tests/Start-DbaAzMigration.Tests.ps1` only if a locally reusable assertion belongs there

- [ ] **Step 1: Add a non-skipping secret-bearing test**

Inside `.github/scripts/gh-actions.ps1`'s `Integration Tests` Describe, add an `It` that:

- Throws immediately if `TENANTID`, `CLIENTID`, or `CLIENTSECRET` is empty.
- Generates a database name by appending the first eight characters of a GUID to `dbatoolsci_azmigration_`.
- Creates the source database on the SQL Server container and creates `dbo.MigrationProof` with deterministic rows.
- Builds the destination connection string in memory with `Authentication=Active Directory Service Principal`, `User Id=$env:CLIENTID`, and `Password=$env:CLIENTSECRET`; never writes it to output.
- Uses a unique `/tmp` directory for BACPAC artifacts.
- Invokes `Start-DbaAzMigration -Source localhost -Destination dbatoolstest.database.windows.net -Database $databaseName -Path $testPath -Confirm:$false -EnableException` using the established source and destination connection objects/credentials supported by the workflow.
- Asserts `Status` is `Successful`, `Type` is `Database`, and `BacpacPath` no longer exists.
- Connects independently to the created Azure database and asserts exact schema/data values.
- In `finally`, removes the Azure database, source database, and local directory.

Do not add `-Skip`, `Set-ItResult -Skipped`, or conditional success. Missing secrets and an unreachable Azure boundary must fail this secret-bearing workflow.

- [ ] **Step 2: Observe the Azure scenario red before relying on it**

Run the scenario against the isolated local Azure logical server provisioned in Task 4, or run an equivalent temporary Pester file using the same code path. The expected initial failure must expose an implementation/authentication/edition issue, not absent credentials.

- [ ] **Step 3: Fix only product defects exposed by the boundary**

Adjust the public command only when the real test reveals incorrect connection reuse, engine detection, import options, status, or cleanup. Keep Azure provisioning out of product code.

- [ ] **Step 4: Exercise safety behaviors at Azure SQL**

In the real scenario (or its local equivalent), invoke the command again without `Force` and assert `Skipped`; modify the destination proof table, invoke with `Force`, and assert the database is recreated with source rows. Invoke with `KeepBacpac`, assert the path exists, and remove it in test cleanup.

- [ ] **Step 5: Commit the Azure scenario**

```powershell
git add .github/scripts/gh-actions.ps1 public/Start-DbaAzMigration.ps1 tests/Start-DbaAzMigration.Tests.ps1
git commit -m "Start-DbaAzMigration - Cover real Azure SQL migration (do Start-DbaAzMigration)"
```

---

## Task 4: Provision an isolated Azure boundary and verify locally

**Files:**

- No tracked product file is created solely for provisioning.
- Temporary credentials and names stay in process memory or ignored temporary files under the worktree and are removed afterward.

- [ ] **Step 1: Resolve exact Azure targets**

Use `az account show` and `az group show --name dbatools-ci` to record the active subscription and resource group. Generate a globally unique lowercase server name and a cryptographically random SQL administrator password without printing the password.

- [ ] **Step 2: Create the isolated logical server**

Use `az sql server create` in `dbatools-ci`, then resolve the caller public IP and add one firewall rule scoped exactly to that address. Do not alter the shared `dbatoolstest` server.

- [ ] **Step 3: Run end-to-end migration**

Create a small local SQL source database and proof table. Create an `ImportDacOption` with a low-cost Azure edition/service objective appropriate for the test. Invoke `Start-DbaAzMigration` using SQL authentication to the isolated destination. Independently connect to the new Azure database and verify exact rows.

- [ ] **Step 4: Verify skip, force, default cleanup, and retention**

Run the same database migration again without `Force`, then with `Force`, and once with `KeepBacpac`. Assert status, destination contents, and filesystem state after every call. Delete the retained BACPAC explicitly.

- [ ] **Step 5: Remove the isolated server in a guaranteed cleanup path**

Delete the exact resolved logical server with Azure CLI. Verify it no longer exists. Remove local source databases and temporary package directories. Never issue a broad resource-group delete.

- [ ] **Step 6: Commit any boundary-driven fixes**

If the real run required code changes, rerun focused tests and commit them with:

```powershell
git commit -m "Start-DbaAzMigration - Fix Azure boundary behavior (do Start-DbaAzMigration)"
```

---

## Task 5: Full verification, review, and completion audit

**Files:**

- Review all files changed from `origin/development`
- Update this checklist only if useful; the plan itself is already committed

- [ ] **Step 1: Run fresh focused Pester verification**

Import the worktree module in a fresh PowerShell process and run:

- `tests/Start-DbaAzMigration.Tests.ps1`
- `tests/Start-DbaMigration.Tests.ps1`
- `tests/Export-DbaDacPackage.Tests.ps1`
- `tests/Publish-DbaDacPackage.Tests.ps1`

Capture the final Pester summary. Required result: zero failed tests.

- [ ] **Step 2: Run repository style and syntax checks**

Run the repository formatter/analyzer command for:

- `public/Start-DbaAzMigration.ps1`
- `tests/Start-DbaAzMigration.Tests.ps1`
- `.github/scripts/gh-actions.ps1`

Search changed PowerShell for `::new(`, backtick line continuations, unresolved placeholders, `-Skip` in the new Azure scenario, and accidental credential output.

- [ ] **Step 3: Verify module packaging**

In a fresh process:

```powershell
Import-Module ./dbatools.psd1 -Force
$command = Get-Command Start-DbaAzMigration -Module dbatools
if (-not $command) { throw "Start-DbaAzMigration is not exported" }
```

Confirm help renders and all parameter types resolve.

- [ ] **Step 4: Audit the final diff**

Review `git diff --check`, `git diff --stat origin/development...HEAD`, every changed hunk, and `git status --short`. Confirm only the approved design, plan, public command, registrations, tests, and GHA integration script changed.

- [ ] **Step 5: Request independent code review and address findings**

Run the repository code-review workflow against `origin/development`. Fix every valid spec, safety, test, or style issue and rerun the affected verification.

- [ ] **Step 6: Confirm Azure cleanup**

Query Azure CLI for the exact isolated server name and confirm it is absent. Confirm no temporary BACPAC or plaintext credential artifact remains locally.

- [ ] **Step 7: Record the final implementation commit if needed**

```powershell
git add public/Start-DbaAzMigration.ps1 tests/Start-DbaAzMigration.Tests.ps1 dbatools.psd1 dbatools.psm1 .github/scripts/gh-actions.ps1
git commit -m "Start-DbaAzMigration - Complete verification fixes (do Start-DbaAzMigration)"
```

- [ ] **Step 8: Report completion**

Report the implemented scope, dependency decision, exact fresh test totals, real Azure proof, Azure cleanup result, branch name, commits, and any genuinely external CI limitation. Do not claim success without fresh command output from Steps 1-6.

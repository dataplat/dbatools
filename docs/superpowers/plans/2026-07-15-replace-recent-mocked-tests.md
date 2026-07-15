# Replace Recent Mocked Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the mock-backed and fabricated-object tests introduced by the prior rolling week of PRs and retain the same behavior coverage with real GitHub, SQL Server, SQL Agent, SSMS local-store, certificate-store, and registry boundaries.

**Architecture:** Reuse the existing `SINGLE`, `MULTI`, and `RESTART` CI boundaries and the fixtures already present in each command test. Keep parameter-contract unit tests, delete redundant mock-only assertions, and add one to three observable integration assertions per changed behavior. Production code is out of scope unless a real integration test demonstrates a defect.

**Tech Stack:** PowerShell 5.1-compatible dbatools code, Pester 6 runner, SQL Server 2017/2019/2022 CI instances, SQL Agent, SSMS Registered Servers local file store, Windows certificate store and SQL Server registry configuration, and public GitHub archives.

## Global Constraints

- Do not change the explicitly approved mocked tests from PR #10438.
- Do not reintroduce the AST test removed by PR #10453.
- Do not use `Mock`, `Should -Invoke`, fabricated SMO objects, source/AST/text assertions, or call-count assertions for the replacement coverage.
- Setup and cleanup must use `EnableException`; missing boundaries fail rather than skip. Version-based skips remain allowed only where the SQL feature is unsupported.
- Use random or `dbatoolsci_`-prefixed object names and restore registry/certificate state in `AfterAll`.
- Keep the existing parameter-validation tests as pure unit tests.

---

### Task 1: Replace download and maintenance refresh mocks with GitHub-backed behavior

**Files:**
- Modify: `tests/Save-DbaCommunitySoftware.Tests.ps1`
- Modify: `tests/Update-DbaMaintenanceSolution.Tests.ps1`

**Interfaces:**
- `Save-DbaCommunitySoftware -Software <name> -LocalDirectory <path> -EnableException`
- `Update-DbaMaintenanceSolution -SqlInstance <instance> -Solution CommandExecute -Confirm:$false -EnableException`

- [x] Replace `Download retry behavior` in `Save-DbaCommunitySoftware.Tests.ps1` with an `IntegrationTests` describe that downloads the Maintenance Solution from its normal GitHub URL into `Join-Path $TestDrive "sql-server-maintenance-solution-main"`.
- [x] Assert the extracted directory contains the real `CommandExecute.sql` file.
- [x] Seed the target with `.gitignore` and `stale.txt`, download again, and assert real GitHub content remains while `stale.txt` is gone. This retains the cache-refresh regression without asserting retries or calls.

```powershell
$targetDirectory = Join-Path -Path $TestDrive -ChildPath "DarlingData-main"
Save-DbaCommunitySoftware -Software DarlingData -LocalDirectory $targetDirectory -EnableException
Get-ChildItem -Path $targetDirectory -Recurse -Filter "*.sql" | Should -Not -BeNullOrEmpty
```

- [x] Replace `Source refresh behavior` in `Update-DbaMaintenanceSolution.Tests.ps1` with an integration fixture on `$TestConfig.InstanceSingle`.
- [x] Create a disposable database with no maintenance procedures, run the command without `LocalFile`, and assert the returned `CommandExecute` row reports `Procedure not installed` after the refresh.
- [x] In `AfterAll`, remove the disposable database and downloaded maintenance cache so the test proves a fresh GitHub acquisition.

```powershell
$result = Update-DbaMaintenanceSolution -SqlInstance $TestConfig.InstanceSingle -Solution CommandExecute -Confirm:$false -EnableException
$result.Procedure | Should -Be "CommandExecute"
$result.IsUpdated | Should -BeTrue
$result.Results | Should -Be "Updated"
```

- [x] Run the two focused files through the repository Pester container with `Get-TestConfig`; expect zero failed tests. Network failure is a test failure, not a skip.
- [x] Commit: `Tests - Use GitHub for community downloads` with body `(do none)`.

---

### Task 2: Replace fabricated registered-server and SQL Agent fixtures

**Files:**
- Modify: `tests/Export-DbaRegServer.Tests.ps1`
- Modify: `tests/Find-DbaAgentJob.Tests.ps1`

**Interfaces:**
- Local `Add/Get/Remove-DbaRegServer` and `Add/Get/Remove-DbaRegServerGroup` calls with no `SqlInstance`
- `Find-DbaAgentJob` against `$TestConfig.InstanceSingle`

- [x] Move the native local registered-server cases into the integration describe and create two random parent paths ending in `Shared` through `Add-DbaRegServerGroup` with no `SqlInstance`.
- [x] Add real local registered servers through `Add-DbaRegServer`, export a server to a generated and explicit path, and assert the resulting files exist with the expected local instance/name components.
- [x] Export the two persisted same-leaf groups to generated and explicit paths and assert two unique files whose names contain each parent plus `Shared`.
- [x] Remove the local registered servers and parent groups in `AfterAll`, and remove every output file created under `TestDrive`.

```powershell
$parentAGroup = Add-DbaRegServerGroup -Name "ParentA\Shared"
$localServer = Add-DbaRegServer -ServerName "localhost\SQLEXPRESS" -Name "LocalAlias" -Group "ParentA\Shared"
$generatedFile = $localServer | Export-DbaRegServer -Path $TestDrive -EnableException
$generatedFile.Exists | Should -BeTrue
```

- [x] Remove the two fabricated `Find-DbaAgentJob` contexts and add an isolated SQL Agent metadata fixture with real prefixed wildcard jobs, including real steps for step-name wildcard coverage.
- [x] Add integration assertions for question-mark/character-class `JobName` wildcards, an escaped literal asterisk plus step wildcard, and regex `Pattern` OR semantics combined with exact `ExcludeJobName` behavior.
- [x] Remove every new job in the isolated fixture's `AfterAll` block.

```powershell
$escapedJobName = [System.Management.Automation.WildcardPattern]::Escape("Literal*Job")
(Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -JobName $escapedJobName).Name | Should -Be "Literal*Job"
(Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Pattern "^Backup\dNightly$", "^ETL2$").Name |
    Should -Be @("Backup1Nightly", "Backup2Nightly", "ETL2")
```

- [x] Run the replacement contexts against the persisted local SSMS store and real SQL Agent metadata in `msdb`: 2 registered-server tests and 3 Agent job/step tests pass with zero failures, and no prefixed jobs remain after cleanup.
- [ ] Commit: `Tests - Use real registered servers and Agent jobs` with body `(do none)`.

---

### Task 3: Replace database and SMO doubles with disposable SQL objects

**Files:**
- Modify: `tests/Invoke-DbaAdvancedRestore.Tests.ps1`
- Modify: `tests/New-DbaDatabase.Tests.ps1`
- Modify: `tests/Invoke-DbaDbShrink.Tests.ps1`
- Modify: `tests/Rename-DbaDatabase.Tests.ps1`
- Modify: `tests/Set-DbaDbCompression.Tests.ps1`
- Modify: `tests/Get-DbaDbOrphanUser.Tests.ps1`

**Interfaces:**
- Existing `SINGLE`/`MULTI` SQL Server instances and current integration fixtures

- [x] Delete only `Should apply RestoreTime only to the final backup` from `Invoke-DbaAdvancedRestore.Tests.ps1`; `Restore-DbaDatabase.Tests.ps1` already performs real full/log restores and asserts exactly one `STOPAT`, on the final log script.
- [x] Delete the fabricated containment test in `New-DbaDatabase.Tests.ps1`, create a random contained database in an isolated `InstanceSingle` integration fixture, and assert the refreshed SMO database reports `Partial`; capture and restore the contained-authentication prerequisite.

```powershell
$containedDatabase = New-DbaDatabase -SqlInstance $InstanceSingle -Name $containmentDbName -ContainmentType Partial
$containedDatabase.Refresh()
$containedDatabase.ContainmentType | Should -Be "Partial"
```

- [x] Remove `New-MockShrinkDatabase` and all mock/call-count assertions from `Invoke-DbaDbShrink.Tests.ps1`.
- [x] Add a second real data file in the focused case. Assert `-FileName` shrinks only the requested logical file and a missing logical name returns no result plus the real warning.
- [x] Exercise the friendly/exception failure paths against the only real primary data file with `-ShrinkMethod EmptyFile`: friendly mode returns `Success = $false` with SQL error details; `-EnableException` rethrows the original SQL error. Do not assert internal `Stop-Function` usage.

```powershell
$result = @(Invoke-DbaDbShrink -InputObject $db -FileType Data -FileName $db.Name -ShrinkMethod EmptyFile -WarningAction SilentlyContinue)
$result.Success | Should -BeFalse
$result.Notes | Should -Not -BeNullOrEmpty
```

- [x] Delete `New-MockRenameDatabase` and its `Get-DbaFile` mock. Add two preview cases to the existing `dbatoolsci_filemove` database: one for row/log logical overrides and one for row/log physical overrides/default `<FT>` behavior, asserting `LGN`/`FNN` mappings from the real database files.
- [x] Delete the fabricated compression fixture and mock-backed table/view selection context.
- [x] Extend the existing compression database with real `dbo` and `sales` tables plus schema-bound indexed views. Assert schema-qualified `-Table` and `-View` select only the requested object, and `-View` without explicit `CompressionType` throws with `-EnableException`.
- [x] Retain the existing all-object and indexed-view integration cases as the replacement for the redundant mocked no-filter case.
- [x] Delete the fabricated orphan-user context. Extend the existing real fixture with a partial-contained database and contained SQL user, plus a certificate and certificate user in the ordinary database. Assert the contained SQL user is not returned and the non-contained certificate user is returned.
- [x] Fix the production certificate-user predicate exposed by the real test: SQL-login users retain the 16-byte SID requirement while certificate-mapped users are classified by their real 32-byte SID/login type.
- [x] Clean up both databases, certificates/users through database removal, and all server logins with `EnableException`; restore contained authentication.
- [x] Run all 12 new SQL-backed assertions available on `InstanceSingle`; expect zero failures. Confirm the redundant restore case maps to the existing real `STOPAT` assertion and leave the full scenario matrix to final CI verification.
- [x] Commit: `Tests - Use disposable SQL objects for regressions` with body `(do none)`.

---

### Task 4: Replace certificate and Extended Protection mocks with Windows boundaries

**Files:**
- Modify: `tests/Set-DbaNetworkCertificate.Tests.ps1`
- Modify: `tests/Get-DbaExtendedProtection.Tests.ps1`
- Modify: `tests/Set-DbaExtendedProtection.Tests.ps1`

**Interfaces:**
- `$TestConfig.InstanceRestart`
- Windows LocalMachine certificate store and SQL Server instance registry configuration

- [x] Remove the mock-backed `RestartService` and `Force` contexts from `Set-DbaNetworkCertificate.Tests.ps1`; retain the existing real certificate lifecycle fixture.
- [x] Add a real `Force` case that creates a self-signed LocalMachine document-encryption certificate without the required Server Authentication EKU, verifies `Test-DbaNetworkCertificate` reports it unsuitable, applies it by thumbprint with `-Force`, and verifies the configured thumbprint through `Test-DbaNetworkCertificate`.
- [x] Use the existing suitable-certificate pipeline/restart case to cover service restart behavior; do not assert an internal command invocation.
- [x] Unset the configured certificate and remove all created certificates in `AfterAll`.

```powershell
$result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -Thumbprint $unsuitableCertificate.Thumbprint -Force -Confirm:$false -EnableException
$result.CertificateThumbprint | Should -Be $unsuitableCertificate.Thumbprint
(Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart).ConfiguredCertificateThumbprint |
    Should -Be $unsuitableCertificate.Thumbprint
```

- [x] Remove the accepted-SPN mocks from both Extended Protection test files and remove the older mocked `IntegrationTests` context in the setter while the file is being repaired.
- [x] In each real fixture, capture the original Extended Protection value and accepted SPNs from `$TestConfig.InstanceRestart` and restore both in `AfterAll`.
- [x] In `Get-DbaExtendedProtection.Tests.ps1`, write two accepted SPNs with the real setter and assert the getter returns two individual values.
- [x] In `Set-DbaExtendedProtection.Tests.ps1`, assert writing `Required` plus two SPNs round-trips through the getter; changing only `Value` preserves SPNs; changing only `AcceptedSpn` preserves the Extended Protection value; and an empty string clears the registry value.
- [ ] Run all three focused files on the `RESTART` runner; expect zero failed tests and confirm original registry/certificate state is restored.
  - [x] Parse and forbidden-construct scans pass locally. A real local Extended Protection run reached the registry boundary and failed because the desktop console is not UAC-elevated; final execution remains assigned to the elevated `RESTART` runner.
- [ ] Commit: `Tests - Use real certificate and registry boundaries` with body `(do none)`.

---

### Task 5: Audit the resulting patch and run repository verification

**Files:**
- Verify all files modified in Tasks 1-4

- [ ] Compare the patch against the audited PR list: #10415, #10424, #10425, #10426, #10428, #10434, #10435, #10437, #10440, #10441, #10442, #10443, and #10444 are addressed; #10438 remains unchanged; #10451 remains superseded by #10453.
- [ ] Scan added lines and affected replacement contexts for forbidden constructs:

```powershell
git diff --unified=0 development...HEAD -- tests | rg "^\+.*\b(Mock|Should\s+-Invoke|InModuleScope)\b|^\+.*New-Object\s+Microsoft\.SqlServer\.Management\.Smo"
```

Expected: no matches in replacement coverage. Any unrelated retained pre-existing match must be identified by `git blame` and must not be part of the new patch.

- [ ] Parse every changed PowerShell test file with `[System.Management.Automation.Language.Parser]::ParseFile`; expect zero parse errors.
- [ ] Run PSScriptAnalyzer on every changed PowerShell test file using the repository settings; expect zero new diagnostics.
- [ ] Run the focused unit tests locally where no external boundary is required, then rely on the existing Azure/AppVeyor scenario matrix for `SINGLE`, `MULTI`, and `RESTART` integration execution.
- [ ] Review `git diff --check`, `git status --short`, and the final diff. Confirm cleanup is symmetrical, no unrelated user changes were touched, and no skipped placeholder replaces a missing dependency.
- [ ] Commit any verification-only corrections with a scoped `Tests - ...` subject and `(do none)` body. Do not publish or merge unless separately requested.

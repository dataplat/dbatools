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

- [ ] Replace `Download retry behavior` in `Save-DbaCommunitySoftware.Tests.ps1` with an `IntegrationTests` describe that downloads `DarlingData` from its normal GitHub URL into `Join-Path $TestDrive "DarlingData-main"`.
- [ ] Assert the extracted directory contains at least one real `.sql` file.
- [ ] Seed the target with `.gitignore` and `stale.txt`, download again, and assert real GitHub content remains while `stale.txt` is gone. This retains the cache-refresh regression without asserting retries or calls.

```powershell
$targetDirectory = Join-Path -Path $TestDrive -ChildPath "DarlingData-main"
Save-DbaCommunitySoftware -Software DarlingData -LocalDirectory $targetDirectory -EnableException
Get-ChildItem -Path $targetDirectory -Recurse -Filter "*.sql" | Should -Not -BeNullOrEmpty
```

- [ ] Replace `Source refresh behavior` in `Update-DbaMaintenanceSolution.Tests.ps1` with an integration fixture on `$TestConfig.InstanceSingle`.
- [ ] Preserve any existing `master.dbo.CommandExecute` definition, create a disposable stub when needed, run the command without `LocalFile`, and assert the returned `CommandExecute` row has `IsUpdated = $true` and `Results = "Updated"`.
- [ ] In `AfterAll`, drop the test procedure and recreate the prior definition when one existed; remove the downloaded maintenance cache so the test proves a fresh GitHub acquisition.

```powershell
$result = Update-DbaMaintenanceSolution -SqlInstance $TestConfig.InstanceSingle -Solution CommandExecute -Confirm:$false -EnableException
$result.Procedure | Should -Be "CommandExecute"
$result.IsUpdated | Should -BeTrue
$result.Results | Should -Be "Updated"
```

- [ ] Run the two focused files through the repository Pester container with `Get-TestConfig`; expect zero failed tests. Network failure is a test failure, not a skip.
- [ ] Commit: `Tests - Use GitHub for community downloads` with body `(do none)`.

---

### Task 2: Replace fabricated registered-server and SQL Agent fixtures

**Files:**
- Modify: `tests/Export-DbaRegServer.Tests.ps1`
- Modify: `tests/Find-DbaAgentJob.Tests.ps1`

**Interfaces:**
- Local `Add/Get/Remove-DbaRegServer` and `Add/Get/Remove-DbaRegServerGroup` calls with no `SqlInstance`
- `Find-DbaAgentJob` against `$TestConfig.InstanceSingle`

- [ ] Move the native local registered-server cases into the integration describe and create `ParentA\Shared` and `ParentB\Shared` through `Add-DbaRegServerGroup` with no `SqlInstance`.
- [ ] Add real local registered servers through `Add-DbaRegServer`, export a server to a generated and explicit path, and assert the resulting files exist with the expected local instance/name components.
- [ ] Export the two persisted same-leaf groups to generated and explicit paths and assert two unique files whose names contain `ParentA$Shared` and `ParentB$Shared`.
- [ ] Remove the local registered servers and parent groups in `AfterAll`, and remove every output file created under `TestDrive`.

```powershell
$parentAGroup = Add-DbaRegServerGroup -Name "ParentA\Shared"
$localServer = Add-DbaRegServer -ServerName "localhost\SQLEXPRESS" -Name "LocalAlias" -Group "ParentA\Shared"
$generatedFile = $localServer | Export-DbaRegServer -Path $TestDrive -EnableException
$generatedFile.Exists | Should -BeTrue
```

- [ ] Remove the two fabricated `Find-DbaAgentJob` contexts and extend the existing SQL Agent fixture with real jobs named `Backup1Nightly`, `Backup2Nightly`, `ETL1`, `ETL2`, `Literal*Job`, and `LiteralXJob`, including real steps for step-name wildcard coverage.
- [ ] Add integration assertions for question-mark/character-class `JobName` wildcards, an escaped literal asterisk plus step wildcard, and regex `Pattern` OR semantics combined with exact `ExcludeJobName` behavior.
- [ ] Extend the existing `AfterAll` job cleanup list to remove every new job.

```powershell
$escapedJobName = [System.Management.Automation.WildcardPattern]::Escape("Literal*Job")
(Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -JobName $escapedJobName).Name | Should -Be "Literal*Job"
(Find-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Pattern "^Backup\dNightly$", "^ETL2$").Name |
    Should -Be @("Backup1Nightly", "Backup2Nightly", "ETL2")
```

- [ ] Run both focused files on a host with the local SSMS store and SQL Agent available; expect zero failed tests.
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

- [ ] Delete only `Should apply RestoreTime only to the final backup` from `Invoke-DbaAdvancedRestore.Tests.ps1`; `Restore-DbaDatabase.Tests.ps1` already performs real full/log restores and asserts exactly one `STOPAT`, on the final log script.
- [ ] Delete the fabricated containment test in `New-DbaDatabase.Tests.ps1`, add a random containment database name to the existing integration fixture, create it with `-ContainmentType Partial`, and assert the refreshed SMO database reports `Partial`.

```powershell
$containedDatabase = New-DbaDatabase -SqlInstance $InstanceSingle -Name $containmentDbName -ContainmentType Partial
$containedDatabase.Refresh()
$containedDatabase.ContainmentType | Should -Be "Partial"
```

- [ ] Remove `New-MockShrinkDatabase` and all mock/call-count assertions from `Invoke-DbaDbShrink.Tests.ps1`.
- [ ] Extend the real shrink database fixture with a second data file. Assert `-FileName` shrinks only the requested logical file and a missing logical name returns no result plus the real warning.
- [ ] Exercise the friendly/exception failure paths against the real primary file with `-ShrinkMethod EmptyFile`: friendly mode returns `Success = $false` with SQL error details; `-EnableException` throws. Do not assert internal `Stop-Function` usage.

```powershell
$result = @(Invoke-DbaDbShrink -InputObject $db -FileType Data -FileName $db.Name -ShrinkMethod EmptyFile -WarningAction SilentlyContinue)
$result.Success | Should -BeFalse
$result.Notes | Should -Not -BeNullOrEmpty
```

- [ ] Delete `New-MockRenameDatabase` and its `Get-DbaFile` mock. Add two preview cases to the existing `dbatoolsci_filemove` database: one for row/log logical overrides and one for row/log physical overrides/default `<FT>` behavior, asserting `LGN`/`FNN` mappings from the real database files.
- [ ] Delete the fabricated compression fixture and mock-backed table/view selection context.
- [ ] Extend the existing compression database with real `dbo` and `sales` tables plus schema-bound indexed views. Assert `-Table "sales.Customer"` returns only the sales table, `-View "sales.CustomerView"` returns only that indexed view, and `-View` without explicit `CompressionType` throws with `-EnableException`.
- [ ] Retain the existing all-object and indexed-view integration cases as the replacement for the redundant mocked no-filter case.
- [ ] Delete the fabricated orphan-user context. Extend the existing real fixture with a partial-contained database and contained SQL user, plus a certificate and certificate user in the ordinary database. Assert the contained SQL user is not returned and the non-contained certificate user is returned.
- [ ] Clean up both databases, certificates/users through database removal, and all server logins with `EnableException`.
- [ ] Run the six focused command files plus `tests/Restore-DbaDatabase.Tests.ps1`; expect zero failed tests on the required SQL versions.
- [ ] Commit: `Tests - Use disposable SQL objects for regressions` with body `(do none)`.

---

### Task 4: Replace certificate and Extended Protection mocks with Windows boundaries

**Files:**
- Modify: `tests/Set-DbaNetworkCertificate.Tests.ps1`
- Modify: `tests/Get-DbaExtendedProtection.Tests.ps1`
- Modify: `tests/Set-DbaExtendedProtection.Tests.ps1`

**Interfaces:**
- `$TestConfig.InstanceRestart`
- Windows LocalMachine certificate store and SQL Server instance registry configuration

- [ ] Remove the mock-backed `RestartService` and `Force` contexts from `Set-DbaNetworkCertificate.Tests.ps1`; retain the existing real certificate lifecycle fixture.
- [ ] Add a real `Force` case that creates a self-signed LocalMachine certificate whose DNS name does not match the restart instance, verifies `Test-DbaNetworkCertificate` reports it unsuitable, applies it by thumbprint with `-Force`, and verifies the configured thumbprint through `Test-DbaNetworkCertificate`.
- [ ] Use the existing suitable-certificate pipeline/restart case to cover service restart behavior; do not assert an internal command invocation.
- [ ] Unset the configured certificate and remove all created certificates in `AfterAll`.

```powershell
$result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -Thumbprint $unsuitableCertificate.Thumbprint -Force -Confirm:$false -EnableException
$result.CertificateThumbprint | Should -Be $unsuitableCertificate.Thumbprint
(Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart).ConfiguredCertificateThumbprint |
    Should -Be $unsuitableCertificate.Thumbprint
```

- [ ] Remove the accepted-SPN mocks from both Extended Protection test files and remove the older mocked `IntegrationTests` context in the setter while the file is being repaired.
- [ ] In each real fixture, capture the original Extended Protection value and accepted SPNs from `$TestConfig.InstanceRestart` and restore both in `AfterAll`.
- [ ] In `Get-DbaExtendedProtection.Tests.ps1`, write two accepted SPNs with the real setter and assert the getter returns two individual values.
- [ ] In `Set-DbaExtendedProtection.Tests.ps1`, assert writing `Required` plus two SPNs round-trips through the getter; changing only `Value` preserves SPNs; changing only `AcceptedSpn` preserves the Extended Protection value; and an empty string clears the registry value.
- [ ] Run all three focused files on the `RESTART` runner; expect zero failed tests and confirm original registry/certificate state is restored.
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

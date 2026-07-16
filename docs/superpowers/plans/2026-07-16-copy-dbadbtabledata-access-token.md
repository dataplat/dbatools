# Copy-DbaDbTableData Access Token Preservation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve an authenticated Azure SQL destination access token through `Copy-DbaDbTableData`'s dedicated bulk-copy connection and prove the behavior against real SQL Server and Azure SQL boundaries.

**Architecture:** Keep the command's existing destination resolution and separate streaming connection. When the destination SMO object's underlying `SqlConnection` has an access token, copy it onto a newly created database-scoped `SqlConnection` and construct `SqlBulkCopy` from that opened connection; otherwise retain the current connection-string constructor. Extend the existing cross-platform integration suite, which already provisions local SQL Server and supplies the Azure service-principal secrets.

**Tech Stack:** PowerShell 3-compatible dbatools code, Microsoft.Data.SqlClient, SMO, Pester 6, Docker SQL Server, Azure SQL Database, GitHub Actions.

## Global Constraints

- Target the `development` branch and use squash merge for eventual integration.
- Preserve all existing comments exactly.
- Use double-quoted PowerShell strings, OTBS formatting, aligned hashtables, and no backtick line continuations.
- Do not add mocks, fabricated SMO objects, source/AST/text assertions, or skipped placeholder coverage.
- Missing Azure service-principal configuration or boundary access must fail the behavioral test.
- Make no public parameter or `Connect-DbaInstance` changes.

---

### Task 1: Add the real Azure SQL regression test

**Files:**
- Modify: `.github/scripts/gh-actions.ps1`

**Interfaces:**
- Consumes: `TENANTID`, `CLIENTID`, and `CLIENTSECRET` in GitHub Actions, or `AZURE_SQL_ACCESS_TOKEN` for local execution; the existing `localhost` SQL Server container and `dbatoolstest.database.windows.net/test` Azure SQL database.
- Produces: A Pester behavior test named `copies table data to Azure with a connected access-token destination` that fails on the current implementation and cleans up both boundary tables.

- [ ] **Step 1: Add the boundary-backed test after the existing Azure database test**

```powershell
    It "copies table data to Azure with a connected access-token destination" {
        $sourceTableName = "dbatoolsci_copy_token_source_$(Get-Random)"
        $destinationTableName = "dbatoolsci_copy_token_destination_$(Get-Random)"
        $sourceServer = $null
        $destinationServer = $null

        try {
            $sourceServer = Connect-DbaInstance -SqlInstance "localhost" -SqlCredential $cred -Database "tempdb"

            if ($env:AZURE_SQL_ACCESS_TOKEN) {
                $destinationServer = Connect-DbaInstance -SqlInstance "dbatoolstest.database.windows.net" -Database "test" -AccessToken $env:AZURE_SQL_ACCESS_TOKEN
            } else {
                if (-not $hasAzureServicePrincipal) {
                    throw "TENANTID, CLIENTID, and CLIENTSECRET are required for the Azure SQL access-token integration test."
                }
                $secureSecret = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
                $azureCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $env:CLIENTID, $secureSecret
                $destinationServer = Connect-DbaInstance -SqlInstance "dbatoolstest.database.windows.net" -Database "test" -SqlCredential $azureCredential -Tenant $env:TENANTID
            }

            $destinationServer.ConnectionContext.SqlConnectionObject.AccessToken | Should -Not -BeNullOrEmpty
            $null = $sourceServer.Query("CREATE TABLE dbo.[$sourceTableName] (id int NOT NULL); INSERT dbo.[$sourceTableName] (id) VALUES (1), (2), (3);", "tempdb")
            $null = $destinationServer.Query("CREATE TABLE dbo.[$destinationTableName] (id int NOT NULL);", "test")

            $splatCopy = @{
                SqlInstance         = $sourceServer
                Destination         = $destinationServer
                Database            = "tempdb"
                DestinationDatabase = "test"
                Table               = "dbo.$sourceTableName"
                DestinationTable    = "dbo.$destinationTableName"
                EnableException     = $true
            }
            $result = Copy-DbaDbTableData @splatCopy
            $destinationState = $destinationServer.Query("SELECT COUNT(*) AS CopiedRows, SUM(id) AS IdTotal FROM dbo.[$destinationTableName];", "test")

            $result.RowsCopied | Should -Be 3
            $destinationState.CopiedRows | Should -Be 3
            $destinationState.IdTotal | Should -Be 6
        } finally {
            if ($sourceServer) {
                $null = $sourceServer.Query("DROP TABLE IF EXISTS dbo.[$sourceTableName];", "tempdb")
            }
            if ($destinationServer) {
                $null = $destinationServer.Query("DROP TABLE IF EXISTS dbo.[$destinationTableName];", "test")
            }
        }
    }
```

- [ ] **Step 2: Start or reuse the real local SQL Server boundary**

Run:

```powershell
$containerState = docker inspect --format "{{.State.Running}}" mssql1 2>$null
if ($LASTEXITCODE -ne 0) {
    docker run -p 1433:1433 --name mssql1 --hostname mssql1 -d dbatools/sqlinstance
} elseif ($containerState -ne "true") {
    docker start mssql1
}
```

Then poll `Connect-DbaInstance -SqlInstance "localhost" -SqlCredential $cred` up to 15 times with five-second intervals and throw if all attempts fail; do not skip the test.

- [ ] **Step 3: Run the new test with the logged-in Azure identity and verify RED**

Run:

```powershell
$env:AZURE_SQL_ACCESS_TOKEN = az account get-access-token --resource "https://database.windows.net/" --query accessToken -o tsv
$configuration = New-PesterConfiguration
$configuration.Run.Path = ".github/scripts/gh-actions.ps1"
$configuration.Filter.FullName = "*copies table data to Azure with a connected access-token destination*"
$configuration.Output.Verbosity = "Detailed"
$configuration.Run.PassThru = $true
$result = Invoke-Pester -Configuration $configuration
$env:AZURE_SQL_ACCESS_TOKEN = $null
```

Expected: FAIL in `Copy-DbaDbTableData` because the bulk-copy connection attempts Azure SQL authentication without the destination `SqlConnection.AccessToken`; setup and cleanup both reach their real boundaries.

- [ ] **Step 4: Commit the verified failing behavior test**

```powershell
git add .github/scripts/gh-actions.ps1
git commit -m "Copy-DbaDbTableData - Test Azure access token destination" -m "(do Copy-DbaDbTableData)"
```

### Task 2: Preserve the destination token for bulk copy

**Files:**
- Modify: `public/Copy-DbaDbTableData.ps1`

**Interfaces:**
- Consumes: `Microsoft.SqlServer.Management.Smo.Server.ConnectionContext.SqlConnectionObject.AccessToken` from the already authenticated destination.
- Produces: A dedicated, database-scoped `Microsoft.Data.SqlClient.SqlConnection` carrying the same access token and a `SqlBulkCopy` instance that uses it.

- [ ] **Step 1: Initialize the optional token-backed bulk-copy connection inside the existing copy try block**

Add before the existing `ShouldProcess` blocks:

```powershell
                    $bulkCopyConnection = $null
```

- [ ] **Step 2: Replace the unconditional connection-string `SqlBulkCopy` construction with token-aware construction**

Replace the current constructor with:

```powershell
                        $destinationAccessToken = $destServer.ConnectionContext.SqlConnectionObject.AccessToken
                        if ($destinationAccessToken) {
                            $bulkCopyConnection = New-Object Microsoft.Data.SqlClient.SqlConnection "$connstring;Database=$DestinationDatabase"
                            $bulkCopyConnection.AccessToken = $destinationAccessToken
                            $bulkCopyConnection.Open()
                            $bulkCopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy($bulkCopyConnection, $bulkCopyOptions, $null)
                        } else {
                            $bulkCopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy("$connstring;Database=$DestinationDatabase", $bulkCopyOptions)
                        }
```

- [ ] **Step 3: Dispose the token-backed connection for success and error paths**

Extend the existing `try`/`catch` with:

```powershell
                } catch {
                    Stop-Function -Message "Something went wrong" -ErrorRecord $_ -Target $server -continue
                } finally {
                    if ($bulkCopyConnection) {
                        $bulkCopyConnection.Close()
                        $bulkCopyConnection.Dispose()
                    }
                }
```

- [ ] **Step 4: Run the focused Azure SQL test and verify GREEN**

Run:

```powershell
$env:AZURE_SQL_ACCESS_TOKEN = az account get-access-token --resource "https://database.windows.net/" --query accessToken -o tsv
$configuration = New-PesterConfiguration
$configuration.Run.Path = ".github/scripts/gh-actions.ps1"
$configuration.Filter.FullName = "*copies table data to Azure with a connected access-token destination*"
$configuration.Output.Verbosity = "Detailed"
$configuration.Run.PassThru = $true
$result = Invoke-Pester -Configuration $configuration
$env:AZURE_SQL_ACCESS_TOKEN = $null
if ($result.Result -ne "Passed" -or $result.FailedCount -gt 0) {
    throw "Azure SQL access-token integration test failed."
}
```

Expected: PASS; `RowsCopied` is 3, Azure reports 3 rows with an ID sum of 6, and cleanup drops both tables.

- [ ] **Step 5: Commit the minimal production fix**

```powershell
git add public/Copy-DbaDbTableData.ps1
git commit -m "Copy-DbaDbTableData - Preserve destination access token" -m "(do Copy-DbaDbTableData)"
```

### Task 3: Verify compatibility and publish

**Files:**
- Verify: `public/Copy-DbaDbTableData.ps1`
- Verify: `tests/Copy-DbaDbTableData.Tests.ps1`
- Verify: `.github/scripts/gh-actions.ps1`

**Interfaces:**
- Consumes: the completed production and integration-test commits.
- Produces: parser-clean PowerShell, passing focused Azure behavior, passing existing `Copy-DbaDbTableData` integration coverage, and a draft PR targeting `development`.

- [ ] **Step 1: Run parser and whitespace checks**

```powershell
$tokens = $null
$commandParseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "public/Copy-DbaDbTableData.ps1"), [ref]$tokens, [ref]$commandParseErrors) | Out-Null
$testParseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path ".github/scripts/gh-actions.ps1"), [ref]$tokens, [ref]$testParseErrors) | Out-Null
if ($commandParseErrors.Count -gt 0 -or $testParseErrors.Count -gt 0) {
    throw "PowerShell parser errors found."
}
git diff --check development...HEAD
```

Expected: no parser errors and no whitespace errors.

- [ ] **Step 2: Run the existing command integration tests against the configured SQL boundaries**

```powershell
Import-Module ./dbatools.psd1 -Force
$result = Invoke-Pester tests/Copy-DbaDbTableData.Tests.ps1 -Output Detailed -PassThru
if ($result.Result -ne "Passed" -or $result.FailedCount -gt 0) {
    throw "Copy-DbaDbTableData tests failed."
}
```

Expected: PASS with zero failures. If the second configured SQL boundary is unavailable, provision it rather than skipping the tests.

- [ ] **Step 3: Re-run the focused Azure behavior with a fresh token**

Run:

```powershell
$env:AZURE_SQL_ACCESS_TOKEN = az account get-access-token --resource "https://database.windows.net/" --query accessToken -o tsv
$configuration = New-PesterConfiguration
$configuration.Run.Path = ".github/scripts/gh-actions.ps1"
$configuration.Filter.FullName = "*copies table data to Azure with a connected access-token destination*"
$configuration.Output.Verbosity = "Detailed"
$configuration.Run.PassThru = $true
$result = Invoke-Pester -Configuration $configuration
$env:AZURE_SQL_ACCESS_TOKEN = $null
if ($result.Result -ne "Passed" -or $result.FailedCount -gt 0) {
    throw "Azure SQL access-token integration test failed."
}
```

Expected: PASS with zero failures.

- [ ] **Step 4: Inspect scope and repository state**

```powershell
git status -sb
git diff --stat development...HEAD
git diff development...HEAD -- public/Copy-DbaDbTableData.ps1 .github/scripts/gh-actions.ps1 docs/superpowers
```

Expected: only the design, plan, Azure regression test, and minimal production fix are present.

- [ ] **Step 5: Push and open the draft pull request**

```powershell
git push -u origin codex/fix-10456
```

Create a draft PR targeting `development` titled:

```text
Copy-DbaDbTableData - Preserve destination access tokens
```

The body must explain the access-token loss at `SqlBulkCopy` construction, the separate-connection constraint, the Azure SQL behavioral test, validation results, and `Fixes #10456`.

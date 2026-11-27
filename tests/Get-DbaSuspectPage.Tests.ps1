#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSuspectPage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Database",
                "SqlCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing if suspect pages are present" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dbname = "dbatoolsci_GetSuspectPage"
            $Server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $null = $Server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $Server -Database $dbname

            $null = $db.Query("
            CREATE TABLE dbo.[Example] (id int);
            INSERT dbo.[Example]
            SELECT top 1000 1
            FROM sys.objects")

            # make darn sure suspect pages show up, run twice
            # One deterministic pass replaces the two runs. SQL Server records a page in
            # suspect_pages only when it reads the corrupted copy from disk, so the good copy
            # must neither be served from memory nor be written back over the corruption.
            # Write the dirty pages of the table to disk first, so no later checkpoint overwrites the corruption.
            $null = $db.Query("CHECKPOINT")
            $null = Invoke-DbaDbCorruption -SqlInstance $TestConfig.InstanceSingle -Database $dbname
            # Taking the database offline drops its pages from the buffer pool, so the next read comes from disk.
            $null = Set-DbaDbState -SqlInstance $Server -Database $dbname -Offline -Force
            $null = Set-DbaDbState -SqlInstance $Server -Database $dbname -Online -Force

            $splatReadCorruptedPage = @{
                SqlInstance = $Server
                Database    = $dbname
                Query       = "SELECT COUNT(*) FROM dbo.[Example]"
            }
            $readError = $null
            try {
                $null = Invoke-DbaQuery @splatReadCorruptedPage
            } catch {
                $readError = $PSItem
            } # should fail

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $results = Get-DbaSuspectPage -SqlInstance $server
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $Server -Database $dbname
        }

        It "reads the corrupted page from disk" {
            # Without the failed read nothing is recorded, and the next test could not tell why.
            $readError | Should -Not -BeNullOrEmpty
            $readError.Exception.Message | Should -Match "checksum"
        }

        It "function should find at least one record in suspect_pages table" {
            $results.Database -contains $dbname | Should -Be $true
        }
    }
}
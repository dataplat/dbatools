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
            # The previous value comes back in finally, so a failing setup does not leak it into later tests.
            $hadEnableException = $PSDefaultParameterValues.ContainsKey("*-Dba*:EnableException")
            $previousEnableException = $PSDefaultParameterValues["*-Dba*:EnableException"]
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            try {
                $dbname = "dbatoolsci_GetSuspectPage"
                $Server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
                $null = $Server.Query("Create Database [$dbname]")
                # Only a checksum makes the read of the corrupted page fail; model may carry another setting.
                $null = $Server.Query("ALTER DATABASE [$dbname] SET PAGE_VERIFY CHECKSUM")
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
                # Set-DbaDbState reports a failed transition in Notes instead of throwing, so check both.
                foreach ($transition in "Offline", "Online") {
                    $splatTransition = @{
                        SqlInstance = $Server
                        Database    = $dbname
                        $transition = $true
                        Force       = $true
                    }
                    $state = Set-DbaDbState @splatTransition
                    if ($state.Status -ne $transition.ToUpper()) {
                        throw "Could not set $dbname $transition, it is $($state.Status): $($state.Notes)"
                    }
                }

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
            } finally {
                if ($hadEnableException) {
                    $PSDefaultParameterValues["*-Dba*:EnableException"] = $previousEnableException
                } else {
                    $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
                }
            }

            # The SQL error number and the event type do not depend on the language of the server.
            $readErrorNumbers = @()
            $exception = $readError.Exception
            while ($exception) {
                if ($exception.PSObject.Properties["Number"] -and $exception.PSObject.Properties["Class"]) {
                    $readErrorNumbers += $exception.Number
                }
                $exception = $exception.InnerException
            }

            $results = Get-DbaSuspectPage -SqlInstance $server
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $Server -Database $dbname
        }

        It "reads the corrupted page from disk" {
            # Without the failed read nothing is recorded, and the next test could not tell why.
            $readError | Should -Not -BeNullOrEmpty
            $readErrorNumbers | Should -Contain 824
        }

        It "function should find at least one record in suspect_pages table" {
            $results.Database -contains $dbname | Should -Be $true
        }

        It "reports the page of the fixture database as a bad checksum" {
            @($results | Where-Object { $PSItem.Database -eq $dbname -and $PSItem.EventType -eq "Bad Checksum" }).Count | Should -BeGreaterThan 0
        }
    }
}
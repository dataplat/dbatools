#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Read-DbaTransactionLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "IgnoreLimit",
                "RowLimit",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Read-DbaTransactionLog is read-only (SELECT * FROM fn_dblog). A fresh database with a small
        # table + a few inserts guarantees plenty of transaction-log records to read back.
        $random = Get-Random
        $logDb = "dbatoolsci_txlog_$random"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $logDb
        $splatActivity = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $logDb
            Query       = "CREATE TABLE dbo.LogGen (id INT); INSERT INTO dbo.LogGen (id) VALUES (1),(2),(3),(4),(5);"
        }
        $null = Invoke-DbaQuery @splatActivity

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            if ($logDb) {
                $splatRemove = @{
                    SqlInstance = $TestConfig.InstanceSingle
                    Database    = $logDb
                    ErrorAction = "SilentlyContinue"
                }
                $null = Remove-DbaDatabase @splatRemove
            }
        } finally {
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Reading the transaction log" {
        It "Warns and returns nothing for a database that does not exist" {
            $splatMissing = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "dbatoolsci_nodb_$random"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Read-DbaTransactionLog @splatMissing
            $result | Should -BeNullOrEmpty
            $warn -join " " | Should -Match "does not exist"
        }

        It "Returns fn_dblog records carrying the expected log columns" {
            $splatRead = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $logDb
                RowLimit    = 25
            }
            $result = @(Read-DbaTransactionLog @splatRead)
            $result.Count | Should -BeGreaterThan 0
            $result.Count | Should -BeLessOrEqual 25
            # fn_dblog exposes each log record's columns as properties (names contain spaces)
            $result[0].PSObject.Properties.Name | Should -Contain "Current LSN"
            $result[0].PSObject.Properties.Name | Should -Contain "Operation"
        }

        It "Caps the number of rows with -RowLimit" {
            $splatTwo = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $logDb
                RowLimit    = 2
            }
            $splatTen = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $logDb
                RowLimit    = 10
            }
            $two = @(Read-DbaTransactionLog @splatTwo)
            $ten = @(Read-DbaTransactionLog @splatTen)
            # TOP 2 returns exactly 2 rows, and a larger limit returns more - proving the cap tracks
            # the parameter rather than just reflecting a tiny log.
            $two.Count | Should -Be 2
            $ten.Count | Should -BeGreaterThan $two.Count
        }
    }

    # NOTE: the >0.5 GB live-log guard (Stop-Function "more than 0.5 Gb ... rerun with -IgnoreLimit"
    # unless -IgnoreLimit) is intentionally not exercised - it requires inflating a database's active
    # transaction log past 500 MB, which is impractical to stage in a characterization test. The
    # -RowLimit path (which sets IgnoreLimit implicitly) covers the bounded-read behavior instead.
}
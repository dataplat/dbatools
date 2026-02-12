#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaLastGoodCheckDb",
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
                "ExcludeDatabase",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatConnection = @{
            SqlInstance = $TestConfig.InstanceMulti1
            Database    = "master"
        }
        $server = Connect-DbaInstance @splatConnection
        $server.Query("DBCC CHECKDB")
        $dbname = "dbatoolsci_]_$(Get-Random)"

        $splatDatabase = @{
            SqlInstance = $TestConfig.InstanceMulti1
            Name        = $dbname
            Owner       = "sa"
        }
        $db = New-DbaDatabase @splatDatabase
        $db.Query("DBCC CHECKDB")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        BeforeAll {
            $masterResults = Get-DbaLastGoodCheckDb -SqlInstance $TestConfig.InstanceMulti1 -Database master
            $allResults = Get-DbaLastGoodCheckDb -SqlInstance $TestConfig.InstanceMulti1 -WarningAction SilentlyContinue
            $dbResults = Get-DbaLastGoodCheckDb -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname
        }

        It "LastGoodCheckDb is a valid date" {
            $masterResults.LastGoodCheckDb -ne $null | Should -Be $true
            $masterResults.LastGoodCheckDb -is [datetime] | Should -Be $true
        }

        It "returns more than 3 results" {
            $allResults.Count -gt 3 | Should -Be $true
        }

        It "LastGoodCheckDb is a valid date for database with embedded ] characters" {
            $dbResults.LastGoodCheckDb -ne $null | Should -Be $true
            $dbResults.LastGoodCheckDb -is [datetime] | Should -Be $true
        }

        It "Returns output of the documented type" {
            $masterResults | Should -Not -BeNullOrEmpty
            $masterResults | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $masterResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "DatabaseCreated",
                "LastGoodCheckDb",
                "DaysSinceDbCreated",
                "DaysSinceLastGoodCheckDb",
                "Status",
                "DataPurityEnabled",
                "CreateVersion",
                "DbccFlags"
            )
            foreach ($prop in $expectedProperties) {
                $masterResults.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Has valid values for standard connection properties" {
            if (-not $masterResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $masterResults.ComputerName | Should -Not -BeNullOrEmpty
            $masterResults.InstanceName | Should -Not -BeNullOrEmpty
            $masterResults.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Has a valid Status value" {
            if (-not $masterResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $masterResults.Status | Should -BeIn @("Ok", "New database, not checked yet", "CheckDB should be performed")
        }
    }

    Context "Piping works" {
        BeforeAll {
            $serverConnection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $serverPipeResults = $serverConnection | Get-DbaLastGoodCheckDb -Database $dbname, master

            $databases = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname, master
            $databasePipeResults = $databases | Get-DbaLastGoodCheckDb
        }

        It "LastGoodCheckDb accepts piped input from Connect-DbaInstance" {
            $serverPipeResults.Count -eq 2 | Should -Be $true
        }

        It "LastGoodCheckDb accepts piped input from Get-DbaDatabase" {
            $databasePipeResults.Count -eq 2 | Should -Be $true
        }
    }

    Context "Doesn't return duplicate results" {
        BeforeAll {
            $duplicateResults = Get-DbaLastGoodCheckDb -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $dbname
        }

        It "LastGoodCheckDb doesn't return duplicates when multiple servers are passed in" {
            ($duplicateResults | Group-Object SqlInstance, Database | Where-Object Count -gt 1) | Should -BeNullOrEmpty
        }
    }

}
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaMaxDop",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "MaxDop",
                "InputObject",
                "AllDatabases",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Input validation" {
        BeforeAll {
            Mock Stop-Function { } -ModuleName dbatools
        }
        It "Should Call Stop-Function. -Database, -AllDatabases and -ExcludeDatabase are mutually exclusive." {
            Set-DbaMaxDop -SqlInstance $TestConfig.instance1 -MaxDop 12 -Database $singledb -AllDatabases -ExcludeDatabase "master" | Should -Be
        }
        It "Validates that Stop Function Mock has been called" {
            $assertMockParams = @{
                CommandName = "Stop-Function"
                Times       = 1
                Exactly     = $true
                Module      = "dbatools"
            }
            Assert-MockCalled @assertMockParams
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $singledb = "dbatoolsci_singledb"
        $dbs = "dbatoolsci_lildb", "dbatoolsci_testMaxDop", $singledb
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbs | Remove-DbaDatabase -Confirm:$false
        foreach ($db in $dbs) {
            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "CREATE DATABASE $db"
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "CREATE DATABASE $db"
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbs | Remove-DbaDatabase -Confirm:$false
        Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbs | Remove-DbaDatabase -Confirm:$false
    }

    Context "Apply to multiple instances" {
        BeforeAll {
            $results = Set-DbaMaxDop -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -MaxDop 2
        }

        It "Returns MaxDop 2 for each instance" {
            foreach ($result in $results) {
                $result.CurrentInstanceMaxDop | Should -Be 2
            }
        }
    }

    Context "Connects to 2016+ instance and apply configuration to single database" {
        BeforeAll {
            $results = Set-DbaMaxDop -SqlInstance $TestConfig.instance2 -MaxDop 4 -Database $singledb
        }

        It "Returns 4 for each database" {
            foreach ($result in $results) {
                $result.DatabaseMaxDop | Should -Be 4
            }
        }
    }

    Context "Connects to 2016+ instance and apply configuration to multiple databases" {
        BeforeAll {
            $results = Set-DbaMaxDop -SqlInstance $TestConfig.instance2 -MaxDop 8 -Database $dbs
        }

        It "Returns 8 for each database" {
            foreach ($result in $results) {
                $result.DatabaseMaxDop | Should -Be 8
            }
        }
    }

    Context "Piping from Test-DbaMaxDop works" {
        BeforeAll {
            $results = Test-DbaMaxDop -SqlInstance $TestConfig.instance2 | Set-DbaMaxDop -MaxDop 4
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        }

        It "Command returns output" {
            $results.CurrentInstanceMaxDop | Should -Not -BeNullOrEmpty
            $results.CurrentInstanceMaxDop | Should -Be 4
        }

        It "Maxdop should match expected" {
            $server.Configuration.MaxDegreeOfParallelism.ConfigValue | Should -Be 4
        }
    }

    Context "Piping SqlInstance name works" {
        BeforeAll {
            $results = $TestConfig.instance2 | Set-DbaMaxDop -MaxDop 2
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        }

        It "Command returns output" {
            $results.CurrentInstanceMaxDop | Should -Not -BeNullOrEmpty
            $results.CurrentInstanceMaxDop | Should -Be 2
        }

        It "Maxdop should match expected" {
            $server.Configuration.MaxDegreeOfParallelism.ConfigValue | Should -Be 2
        }
    }
}

#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaMaxDop",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

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
            $singledb = "dbatoolsci_singledb"
        }

        It "Should Call Stop-Function. -Database, -AllDatabases and -ExcludeDatabase are mutually exclusive." {
            Set-DbaMaxDop -SqlInstance $TestConfig.instance1 -MaxDop 12 -Database $singledb -AllDatabases -ExcludeDatabase "master" | Should -Be $null
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
        $global:singledb = "dbatoolsci_singledb"
        $global:dbs = "dbatoolsci_lildb", "dbatoolsci_testMaxDop", $global:singledb
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $global:dbs | Remove-DbaDatabase -Confirm:$false
        foreach ($db in $global:dbs) {
            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "CREATE DATABASE $db"
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "CREATE DATABASE $db"
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $global:dbs -ErrorAction SilentlyContinue | Remove-DbaDatabase -Confirm:$false
        Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $global:dbs -ErrorAction SilentlyContinue | Remove-DbaDatabase -Confirm:$false
    }

    Context "Apply to multiple instances" {
        BeforeAll {
            $multiInstanceResults = Set-DbaMaxDop -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -MaxDop 2
        }

        It "Returns MaxDop 2 for each instance" {
            foreach ($result in $multiInstanceResults) {
                $result.CurrentInstanceMaxDop | Should -Be 2
            }
        }
    }

    Context "Connects to 2016+ instance and apply configuration to single database" {
        BeforeAll {
            $singleDbResults = Set-DbaMaxDop -SqlInstance $TestConfig.instance2 -MaxDop 4 -Database $global:singledb
        }

        It "Returns 4 for each database" {
            foreach ($result in $singleDbResults) {
                $result.DatabaseMaxDop | Should -Be 4
            }
        }
    }

    Context "Connects to 2016+ instance and apply configuration to multiple databases" {
        BeforeAll {
            $multiDbResults = Set-DbaMaxDop -SqlInstance $TestConfig.instance2 -MaxDop 8 -Database $global:dbs
        }

        It "Returns 8 for each database" {
            foreach ($result in $multiDbResults) {
                $result.DatabaseMaxDop | Should -Be 8
            }
        }
    }

    Context "Piping from Test-DbaMaxDop works" {
        BeforeAll {
            $pipeTestResults = Test-DbaMaxDop -SqlInstance $TestConfig.instance2 | Set-DbaMaxDop -MaxDop 4
            $pipeTestServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        }

        It "Command returns output" {
            $pipeTestResults.CurrentInstanceMaxDop | Should -Not -BeNullOrEmpty
            $pipeTestResults.CurrentInstanceMaxDop | Should -Be 4
        }

        It "Maxdop should match expected" {
            $pipeTestServer.Configuration.MaxDegreeOfParallelism.ConfigValue | Should -Be 4
        }
    }

    Context "Piping SqlInstance name works" {
        BeforeAll {
            $pipeInstanceResults = $TestConfig.instance2 | Set-DbaMaxDop -MaxDop 2
            $pipeInstanceServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        }

        It "Command returns output" {
            $pipeInstanceResults.CurrentInstanceMaxDop | Should -Not -BeNullOrEmpty
            $pipeInstanceResults.CurrentInstanceMaxDop | Should -Be 2
        }

        It "Maxdop should match expected" {
            $pipeInstanceServer.Configuration.MaxDegreeOfParallelism.ConfigValue | Should -Be 2
        }
    }
}
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaMaxDop",
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
                "MaxDop",
                "InputObject",
                "AllDatabases",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Input validation" {
        It "Should Call Stop-Function. -Database, -AllDatabases and -ExcludeDatabase are mutually exclusive." {
            Mock Stop-Function { } -ModuleName dbatools
            $singledb = "dbatoolsci_singledb"
            Set-DbaMaxDop -SqlInstance $TestConfig.InstanceMulti1 -MaxDop 12 -Database $singledb -AllDatabases -ExcludeDatabase "master" | Should -Be $null
            Should -Invoke Stop-Function -Times 1 -Exactly -ModuleName dbatools
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $singledb = "dbatoolsci_singledb"
        $dbs = "dbatoolsci_lildb", "dbatoolsci_testMaxDop", $singledb
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $dbs | Remove-DbaDatabase
        foreach ($db in $dbs) {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query "CREATE DATABASE $db"
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query "CREATE DATABASE $db"
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $dbs | Remove-DbaDatabase
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $dbs | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Apply to multiple instances" {
        It "Returns MaxDop 2 for each instance" {
            $results = Set-DbaMaxDop -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -MaxDop 2 -OutVariable "global:dbatoolsciInstanceOutput"
            foreach ($result in $results) {
                $result.CurrentInstanceMaxDop | Should -Be 2
            }
        }
    }

    Context "Connects to 2016+ instance and apply configuration to single database" {
        It "Returns 4 for each database" {
            $results = Set-DbaMaxDop -SqlInstance $TestConfig.InstanceMulti2 -MaxDop 4 -Database $singledb
            foreach ($result in $results) {
                $result.DatabaseMaxDop | Should -Be 4
            }
        }
    }

    Context "Connects to 2016+ instance and apply configuration to multiple databases" {
        It "Returns 8 for each database" {
            $results = Set-DbaMaxDop -SqlInstance $TestConfig.InstanceMulti2 -MaxDop 8 -Database $dbs
            foreach ($result in $results) {
                $result.DatabaseMaxDop | Should -Be 8
            }
        }
    }

    Context "Piping from Test-DbaMaxDop works" {
        BeforeAll {
            $results = Test-DbaMaxDop -SqlInstance $TestConfig.InstanceMulti2 | Set-DbaMaxDop -MaxDop 4
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
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
            $results = $TestConfig.InstanceMulti2 | Set-DbaMaxDop -MaxDop 2
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        }

        It "Command returns output" {
            $results.CurrentInstanceMaxDop | Should -Not -BeNullOrEmpty
            $results.CurrentInstanceMaxDop | Should -Be 2
        }

        It "Maxdop should match expected" {
            $server.Configuration.MaxDegreeOfParallelism.ConfigValue | Should -Be 2
        }
    }

    Context "Output validation for instance-level results" {
        AfterAll {
            $global:dbatoolsciInstanceOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciInstanceOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "InstanceVersion",
                "Database",
                "DatabaseMaxDop",
                "CurrentInstanceMaxDop",
                "RecommendedMaxDop",
                "PreviousDatabaseMaxDopValue",
                "PreviousInstanceMaxDopValue"
            )
            $actualProperties = $global:dbatoolsciInstanceOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns for instance-level output" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "PreviousInstanceMaxDopValue",
                "CurrentInstanceMaxDop"
            )
            $defaultColumns = $global:dbatoolsciInstanceOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }

}
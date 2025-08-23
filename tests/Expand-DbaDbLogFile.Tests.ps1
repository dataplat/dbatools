#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Expand-DbaDbLogFile",
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
                "TargetLogSize",
                "IncrementSize",
                "LogFileId",
                "ShrinkLogFile",
                "ShrinkSize",
                "BackupDirectory",
                "ExcludeDiskSpaceValidation",
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

        # Set variables. They are available in all the It blocks.
        $db1Name = "dbatoolsci_expand"
        $db1 = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $db1Name

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $db1Name

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Ensure command functionality" {
        BeforeAll {
            $results = Expand-DbaDbLogFile -SqlInstance $TestConfig.instance1 -Database $db1 -TargetLogSize 128
        }

        It "Should have correct properties" -Skip:$true {
            $ExpectedProps = "ComputerName", "InstanceName", "SqlInstance", "Database", "ID", "Name", "LogFileCount", "InitialSize", "CurrentSize", "InitialVLFCount", "CurrentVLFCount"
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should have database name and ID of $db1" {
            foreach ($result in $results) {
                $result.Database | Should -Be $db1Name
                $result.DatabaseID | Should -Be $db1.ID
            }
        }

        It "Should have grown the log file" {
            foreach ($result in $results) {
                $result.InitialSize -gt $result.CurrentSize
            }
        }
    }
}
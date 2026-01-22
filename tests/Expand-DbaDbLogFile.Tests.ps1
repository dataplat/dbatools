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
        $db1 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $db1Name

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db1Name

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Expand-DbaDbLogFile -SqlInstance $TestConfig.InstanceSingle -Database $db1Name -TargetLogSize 128 -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'DatabaseID',
                'ID',
                'Name',
                'InitialSize',
                'CurrentSize',
                'InitialVLFCount',
                'CurrentVLFCount'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has LogFileCount property available via Select-Object" {
            $result.PSObject.Properties.Name | Should -Contain 'LogFileCount' -Because "LogFileCount should be accessible even though excluded from default view"
        }
    }

    Context "Ensure command functionality" {
        BeforeAll {
            $results = Expand-DbaDbLogFile -SqlInstance $TestConfig.InstanceSingle -Database $db1Name -TargetLogSize 128
        }

        It "Should have correct properties" {
            $ExpectedProps = "ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseID", "ID", "Name", "LogFileCount", "InitialSize", "CurrentSize", "InitialVLFCount", "CurrentVLFCount"
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should have database name and ID" {
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
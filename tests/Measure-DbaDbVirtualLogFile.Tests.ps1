#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Measure-DbaDbVirtualLogFile",
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
                "IncludeSystemDBs",
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

        $serverInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $testDbName = "dbatoolsci_testvlf"
        $serverInstance.Query("CREATE DATABASE $testDbName")
        $testDatabase = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName
        $setupSucceeded = $true
        if ($testDatabase.Count -ne 1) {
            $setupSucceeded = $false
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        BeforeAll {
            if (-not $setupSucceeded) {
                Set-TestInconclusive -Message "Setup failed"
            }
            $testResults = Measure-DbaDbVirtualLogFile -SqlInstance $TestConfig.InstanceSingle -Database $testDbName
        }

        It "Should have correct properties" {
            $expectedProps = "ComputerName", "InstanceName", "SqlInstance", "Database", "Total", "TotalCount", "Inactive", "Active", "LogFileName", "LogFileGrowth", "LogFileGrowthType"
            ($testResults.PSObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Should have database name of $testDbName" {
            foreach ($result in $testResults) {
                $result.Database | Should -Be $testDbName
            }
        }

        It "Should have values for Total property" {
            foreach ($result in $testResults) {
                $result.Total | Should -Not -BeNullOrEmpty
                $result.Total | Should -BeGreaterThan 0
            }
        }

        It "Returns output of the documented type" {
            $testResults | Should -Not -BeNullOrEmpty
            $testResults[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            if (-not $testResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $testResults[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Total"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected additional properties" {
            if (-not $testResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $additionalProps = @(
                "TotalCount",
                "Inactive",
                "Active",
                "LogFileName",
                "LogFileGrowth",
                "LogFileGrowthType"
            )
            foreach ($prop in $additionalProps) {
                $testResults[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be available"
            }
        }
    }
}
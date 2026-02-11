#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaMaxDop",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $testDbName = "dbatoolsci_testMaxDop"
        $server.Query("CREATE DATABASE dbatoolsci_testMaxDop")
        $testDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName
        $setupSuccessful = $true
        if (-not $testDb) {
            $setupSuccessful = $false
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    # Just not messin with this in appveyor
    Context "Command works on SQL Server 2016 or higher instances" {
        BeforeAll {
            if ($setupSuccessful) {
                $testResults = Test-DbaMaxDop -SqlInstance $TestConfig.InstanceSingle
            }
        }

        It "Should have correct properties" -Skip:(-not $setupSuccessful) {
            $expectedProps = "ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseMaxDop", "CurrentInstanceMaxDop", "RecommendedMaxDop", "Notes"
            foreach ($result in $testResults) {
                ($result.PSStandardMembers.DefaultDIsplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
            }
        }

        It "Should have only one result for database name of dbatoolsci_testMaxDop" -Skip:(-not $setupSuccessful) {
            @($testResults | Where-Object Database -eq $testDbName).Count | Should -Be 1
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputResult = Test-DbaMaxDop -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseMaxDop", "CurrentInstanceMaxDop", "RecommendedMaxDop", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected additional properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $additionalProps = @("InstanceVersion", "NumaNodes", "NumberOfCores")
            foreach ($prop in $additionalProps) {
                $outputResult[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be available"
            }
        }
    }
}
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPlanCache",
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
    Context "When retrieving plan cache information" {
        BeforeAll {
            $result = @(Get-DbaPlanCache -SqlInstance $TestConfig.InstanceSingle)
        }

        It "Returns correct datatypes" {
            $results = Get-DbaPlanCache -SqlInstance $TestConfig.InstanceSingle | Clear-DbaPlanCache -Threshold 1024
            $results.Size -is [dbasize] | Should -Be $true
        }

        It "Returns output" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Size", "UseCount")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Size property is a dbasize object" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].Size | Should -BeOfType [dbasize]
        }
    }
}
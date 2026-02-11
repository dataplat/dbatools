#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaAvailabilityGroup",
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
                "AvailabilityGroup",
                "Secondary",
                "SecondarySqlCredential",
                "AddDatabase",
                "SeedingMode",
                "SharedPath",
                "UseLastBackup",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:(-not $TestConfig.InstanceHadr) {
        BeforeAll {
            $agName = (Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr | Select-Object -First 1).AvailabilityGroup
            if ($agName) {
                $result = Test-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName
            }
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the correct properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "AvailabilityGroup"
            )
            foreach ($prop in $expectedProperties) {
                $result[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgListener",
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
                "Listener",
                "Port",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:(-not $TestConfig.InstanceHadr) {
        BeforeAll {
            $listener = Get-DbaAgListener -SqlInstance $TestConfig.InstanceHadr
            if ($listener) {
                $result = Set-DbaAgListener -InputObject $listener[0] -Port $listener[0].PortNumber
            }
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no listener available to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener"
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no listener available to validate" }
            $result[0].psobject.Properties.Name | Should -Contain "Name"
            $result[0].psobject.Properties.Name | Should -Contain "PortNumber"
        }
    }
}

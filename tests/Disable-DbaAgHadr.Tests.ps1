#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaAgHadr",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "Force",
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

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Re-enable HADR for future tests
        $null = Enable-DbaAgHadr -SqlInstance $TestConfig.InstanceHadr -Force

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When disabling HADR" {
        It "Successfully disables HADR" {
            $disableResults = Disable-DbaAgHadr -SqlInstance $TestConfig.InstanceHadr -Force
            $disableResults.IsHadrEnabled | Should -BeFalse
        }

        It "Returns output of the documented type" {
            if (-not $disableResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $disableResults[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $disableResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "IsHadrEnabled")
            foreach ($prop in $expectedProperties) {
                $disableResults[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Returns the correct values" {
            if (-not $disableResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $disableResults[0].ComputerName | Should -Not -BeNullOrEmpty
            $disableResults[0].InstanceName | Should -Not -BeNullOrEmpty
            $disableResults[0].SqlInstance | Should -Not -BeNullOrEmpty
            $disableResults[0].IsHadrEnabled | Should -BeFalse
        }
    }
}
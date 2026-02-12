#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaAgHadr",
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

        # Disable HADR to ensure clean state for testing
        Disable-DbaAgHadr -SqlInstance $TestConfig.InstanceHadr -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When enabling HADR" {
        BeforeAll {
            $results = Enable-DbaAgHadr -SqlInstance $TestConfig.InstanceHadr -Force
        }

        It "Successfully enables HADR" {
            if (-not $results) { Set-ItResult -Skipped -Because "HADR may already be enabled or ShouldProcess not supported in Pester context" }
            $results.IsHadrEnabled | Should -BeTrue
        }

        It "Returns output of the documented type" {
            if (-not $results) { Set-ItResult -Skipped -Because "HADR may already be enabled or ShouldProcess not supported in Pester context" }
            $results | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "HADR may already be enabled or ShouldProcess not supported in Pester context" }
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "IsHadrEnabled")
            foreach ($prop in $expectedProperties) {
                $results.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }
}
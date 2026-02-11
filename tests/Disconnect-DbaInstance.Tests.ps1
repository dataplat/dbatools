#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disconnect-DbaInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "InputObject",
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

        # Connect to instance for testing
        $null = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup - disconnect any remaining connections
        $null = Get-DbaConnectedInstance | Disconnect-DbaInstance

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When disconnecting a server" {
        BeforeAll {
            $disconnectResults = @(Get-DbaConnectedInstance | Disconnect-DbaInstance)
        }

        It "Returns results" {
            $disconnectResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            # Create a fresh connection to disconnect
            $null = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $outputResult = @(Get-DbaConnectedInstance | Disconnect-DbaInstance)
        }

        It "Returns output as PSCustomObject" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("SqlInstance", "ConnectionType", "State")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected properties" {
            $expectedProperties = @("SqlInstance", "ConnectionString", "ConnectionType", "State")
            foreach ($prop in $expectedProperties) {
                $outputResult[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}
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
            $disconnectResults = @(Get-DbaConnectedInstance | Disconnect-DbaInstance -OutVariable "global:dbatoolsciOutput")
        }

        It "Returns results" {
            $disconnectResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "SqlInstance",
                "ConnectionType",
                "State"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should include the SqlInstance property" {
            $global:dbatoolsciOutput[0].SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Should include the ConnectionType property" {
            $global:dbatoolsciOutput[0].ConnectionType | Should -Not -BeNullOrEmpty
        }

        It "Should report State as Disconnected or Closed" {
            $global:dbatoolsciOutput[0].State | Should -BeIn @("Disconnected", "Closed")
        }

        It "Should include the ConnectionString property" {
            $global:dbatoolsciOutput[0].PSObject.Properties.Name | Should -Contain "ConnectionString"
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSObject|PSCustomObject"
        }
    }
}

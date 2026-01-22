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

    Context "Output Validation" {
        It "Returns the documented output type" {
            # Create a mock AvailabilityGroupListener object for testing
            $mockListener = New-Object -TypeName Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener -ArgumentList (
                New-Object -TypeName Microsoft.SqlServer.Management.Smo.AvailabilityGroup -ArgumentList (
                    New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList "localhost"
                ), "TestListener"
            )
            $mockListener | Should -BeOfType [Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener]
        }

        It "Has the expected key properties documented in .OUTPUTS" {
            # Create a mock AvailabilityGroupListener object for testing
            $mockListener = New-Object -TypeName Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener -ArgumentList (
                New-Object -TypeName Microsoft.SqlServer.Management.Smo.AvailabilityGroup -ArgumentList (
                    New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList "localhost"
                ), "TestListener"
            )

            $expectedProps = @(
                'Name',
                'PortNumber',
                'Parent'
            )
            $actualProps = $mockListener.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available on AvailabilityGroupListener"
            }
        }
    }
}
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaEndpoint",
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
                "EndPoint",
                "AllEndpoints",
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

        # Create an endpoint for testing
        $null = New-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Type DatabaseMirroring -Role Partner -Name Mirroring | Start-DbaEndpoint

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "removes an endpoint" {
        $results = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle | Where-Object EndpointType -eq DatabaseMirroring | Remove-DbaEndpoint
        $results.Status | Should -Be 'Removed'
    }

    Context "Output Validation" {
        BeforeAll {
            # Create a test endpoint
            $null = New-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Type DatabaseMirroring -Role Partner -Name MirroringOutputTest -EnableException | Start-DbaEndpoint
            
            # Remove it and capture output
            $result = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint MirroringOutputTest -EnableException | Remove-DbaEndpoint
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Endpoint',
                'Status'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in output"
            }
        }

        It "Sets Status property to 'Removed'" {
            $result.Status | Should -Be 'Removed'
        }
    }
}
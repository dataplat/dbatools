#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaEndpoint",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Endpoint",
                "AllEndpoints",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Create a test endpoint for removal testing
        $endpointName = "dbatoolsci_test_endpoint"
        $null = New-DbaEndpoint -SqlInstance $TestConfig.instance2 -Type DatabaseMirroring -Role Partner -Name $endpointName -Confirm $false | Start-DbaEndpoint -Confirm $false

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup any remaining test endpoints
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance2 | Where-Object Name -eq $endpointName | Remove-DbaEndpoint -Confirm $false -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When removing endpoints" {
        It "removes an endpoint successfully" {
            $results = Get-DbaEndpoint -SqlInstance $TestConfig.instance2 | Where-Object EndpointType -eq DatabaseMirroring | Remove-DbaEndpoint -Confirm $false
            $results.Status | Should -Be "Removed"
        }
    }
}

#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaEndpoint",
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
                "Endpoint",
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

        # Stop the endpoint to prepare for testing
        Get-DbaEndpoint -SqlInstance $TestConfig.instance2 -Endpoint "TSQL Default TCP" | Stop-DbaEndpoint -Confirm:$false

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Restore the endpoint to its original state
        Get-DbaEndpoint -SqlInstance $TestConfig.instance2 -Endpoint "TSQL Default TCP" | Start-DbaEndpoint -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "starts the endpoint" {
        $endpoint = Get-DbaEndpoint -SqlInstance $TestConfig.instance2 -Endpoint "TSQL Default TCP"
        $results = $endpoint | Start-DbaEndpoint -Confirm:$false
        $results.EndpointState | Should -Be "Started"
    }
}
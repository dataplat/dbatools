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

        $endpointName = "dbatoolsci_removeep"

        # Clean up any leftover endpoint from a previous test run
        $existing = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $endpointName -ErrorAction SilentlyContinue
        if ($existing) {
            $null = $existing | Remove-DbaEndpoint -Confirm:$false
        }

        # Create an endpoint for testing
        $splatEndpoint = @{
            SqlInstance = $TestConfig.InstanceSingle
            Type       = "DatabaseMirroring"
            Role       = "Partner"
            Name       = $endpointName
        }
        $null = New-DbaEndpoint @splatEndpoint | Start-DbaEndpoint

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "removes an endpoint" {
        $results = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $endpointName | Remove-DbaEndpoint -Confirm:$false
        $script:outputValidationResult = $results
        $results.Status | Should -Be "Removed"
    }

    Context "Output validation" {
        It "Returns output of the expected type" {
            if (-not $script:outputValidationResult) { Set-ItResult -Skipped -Because "no result to validate"; return }
            $script:outputValidationResult | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $script:outputValidationResult) { Set-ItResult -Skipped -Because "no result to validate"; return }
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Endpoint", "Status")
            foreach ($prop in $expectedProperties) {
                $script:outputValidationResult[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has the correct values for a successful removal" {
            if (-not $script:outputValidationResult) { Set-ItResult -Skipped -Because "no result to validate"; return }
            $script:outputValidationResult[0].Status | Should -Be "Removed"
        }
    }
}
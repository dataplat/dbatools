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

        # Clean up any stale mirroring endpoints before creating a new one
        $staleEps = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle | Where-Object EndpointType -eq DatabaseMirroring
        foreach ($staleEp in $staleEps) {
            try { $staleEp.Parent.Query("DROP ENDPOINT [$($staleEp.Name)]") } catch { }
        }
        $script:outputEndpointName = "dbatoolsci_ep_output_$(Get-Random)"
        $outputInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = $outputInstance.Query("CREATE ENDPOINT [$script:outputEndpointName] STATE = STARTED AS TCP (LISTENER_PORT = 5023) FOR DATABASE_MIRRORING (ROLE = PARTNER)")
        $script:outputValidationResult = Remove-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $script:outputEndpointName -Confirm:$false | Where-Object { $null -ne $PSItem }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "removes an endpoint" {
        $results = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle | Where-Object EndpointType -eq DatabaseMirroring | Remove-DbaEndpoint
        $results.Status | Should -Be 'Removed'
    }

    Context "Output validation" {
        It "Returns output of the expected type" {
            $script:outputValidationResult | Should -Not -BeNullOrEmpty
            $script:outputValidationResult | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $script:outputValidationResult | Should -Not -BeNullOrEmpty
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Endpoint", "Status")
            foreach ($prop in $expectedProperties) {
                $script:outputValidationResult.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has the correct values for a successful removal" {
            $script:outputValidationResult | Should -Not -BeNullOrEmpty
            $script:outputValidationResult.Status | Should -Be "Removed"
            $script:outputValidationResult.Endpoint | Should -Be $script:outputEndpointName
        }
    }
}
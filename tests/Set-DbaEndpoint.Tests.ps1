#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaEndpoint",
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
                "Owner",
                "Type",
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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any stale mirroring endpoints before creating a new one
        $staleEps = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle | Where-Object EndpointType -eq DatabaseMirroring
        foreach ($staleEp in $staleEps) {
            try { $staleEp.Parent.Query("DROP ENDPOINT [$($staleEp.Name)]") } catch { }
        }

        $endpointName = "dbatoolsci_setep_$(Get-Random)"
        $instance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = $instance.Query("CREATE ENDPOINT [$endpointName] STATE = STARTED AS TCP (LISTENER_PORT = 5024) FOR DATABASE_MIRRORING (ROLE = PARTNER)")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        try {
            $cleanupInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $cleanupInstance.Query("IF EXISTS (SELECT 1 FROM sys.endpoints WHERE name = '$endpointName') DROP ENDPOINT [$endpointName]")
        } catch { }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output validation" {
        BeforeAll {
            $result = Set-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $endpointName -Owner sa
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Endpoint"
        }

        It "Has the expected endpoint properties" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].Name | Should -Be $endpointName
            $result[0].Owner | Should -Be "sa"
            $result[0].EndpointType | Should -Be "DatabaseMirroring"
        }
    }
}
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaNetworkCertificate",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Command works against a default instance" {
        BeforeAll {
            $results = Get-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceSingle -WarningVariable warn 3> $null
        }

        It "Should run without warning" {
            # Instances using SQL Server's auto-generated fallback certificate have no explicitly
            # configured network certificate, so no object is returned; when one is configured this
            # returns one certificate object per instance.
            $warn | Should -BeNullOrEmpty
        }

        It "Returns only certificate objects that carry a Thumbprint" {
            foreach ($result in $results) {
                $result.Thumbprint | Should -Not -BeNullOrEmpty
            }
        }
    }
}
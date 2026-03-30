#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaNetworkEncryption",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Certificate retrieval" {
        BeforeAll {
            # Attempt to retrieve the certificate - not all environments have TLS configured
            $result = Get-DbaNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
        }

        It "Should return certificate with expected properties when TLS is configured" {
            if ($null -eq $result) {
                Set-ItResult -Skipped -Because "No TLS certificate is configured on this SQL Server instance"
            }
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Subject | Should -Not -BeNullOrEmpty
            $result.Thumbprint | Should -Not -BeNullOrEmpty
            $result.Expires | Should -BeOfType [datetime]
            $result.NotBefore | Should -BeOfType [datetime]
        }
    }
}
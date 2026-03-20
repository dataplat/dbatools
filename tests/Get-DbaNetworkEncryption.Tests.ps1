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
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Certificate retrieval" {
        BeforeAll {
            # Attempt to retrieve the certificate - not all environments have TLS configured
            $result = Get-DbaNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
        }

        It "Should not throw an error when connecting" {
            # If result is null it means no certificate is configured, which is a valid state
            # We just verify the command runs without throwing a terminating error
            { Get-DbaNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It "Should return certificate with expected properties when TLS is configured" {
            if ($null -eq $result) {
                Set-ItResult -Skipped -Because "No TLS certificate is configured on this SQL Server instance"
            }
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Port | Should -BeGreaterThan 0
            $result.Subject | Should -Not -BeNullOrEmpty
            $result.Thumbprint | Should -Not -BeNullOrEmpty
        }

        It "Should return valid expiration date when TLS is configured" {
            if ($null -eq $result) {
                Set-ItResult -Skipped -Because "No TLS certificate is configured on this SQL Server instance"
            }
            $result.Expires | Should -BeOfType [datetime]
            $result.NotBefore | Should -BeOfType [datetime]
        }
    }
}

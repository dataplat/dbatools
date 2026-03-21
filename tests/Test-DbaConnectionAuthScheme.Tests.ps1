#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaConnectionAuthScheme",
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
                "Kerberos",
                "Ntlm",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "returns the proper transport" {
        It "returns ntlm auth scheme" {
            $results = Test-DbaConnectionAuthScheme -SqlInstance $TestConfig.InstanceSingle
            if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
                $results.AuthScheme | Should -Be 'ntlm'
            } else {
                $results.AuthScheme | Should -Be 'KERBEROS'
            }

        }
    }
}
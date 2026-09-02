#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPbmStore",
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
    # This Describe deliberately carries no pwsh skip: until #10662 the command refused to run on
    # PowerShell 7 even on Windows, so running it here on both editions is the regression test.

    Context "Getting the policy store" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $results = Get-DbaPbmStore -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns the store of the instance without warnings" {
            $WarnVar | Should -BeNullOrEmpty
            $results | Should -Not -BeNullOrEmpty
            $results.SqlInstance | Should -Be $server.DomainInstanceName
        }

        It "Reaches the policies through the store" {
            $results.Policies.Count | Should -BeGreaterThan 0
        }
    }
}

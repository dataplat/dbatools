#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaReplServer",
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
    Context "When reading the replication server role on a non-distributor instance" {
        BeforeAll {
            $results = Get-DbaReplServer -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns a ReplicationServer object" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Reports the instance is not configured as a distributor" {
            $results.IsDistributor | Should -Be $false
        }

        It "Decorates the instance identity columns" {
            $results.ComputerName | Should -Not -BeNullOrEmpty
            $results.InstanceName | Should -Not -BeNullOrEmpty
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}
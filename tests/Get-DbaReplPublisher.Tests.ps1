#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaReplPublisher",
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
    # Characterization tests (2026-07-06, Track A): pin the observed behavior of the live
    # implementation ahead of the C# port. Distribution is configured on InstanceCopy1
    # (local distributor+publisher, distribution db "distribution", working directory
    # \\dc1\DbaToolsTemp); InstanceSingle must stay distributor-free.
    Context "When the instance is a distributor with a local publisher" {
        BeforeAll {
            $publisherResults = @(Get-DbaReplPublisher -SqlInstance $TestConfig.InstanceCopy1 -WarningAction SilentlyContinue)
        }

        It "Returns exactly one DistributionPublisher" {
            $publisherResults.Count | Should -Be 1
            $publisherResults[0].PSObject.TypeNames[0] | Should -Match "DistributionPublisher"
        }

        It "Reports the local distribution topology" {
            $publisherResults[0].Status | Should -Be "Active"
            $publisherResults[0].DistributionDatabase | Should -Be "distribution"
            $publisherResults[0].WorkingDirectory | Should -Not -BeNullOrEmpty
            $publisherResults[0].PublisherType | Should -Be "MSSQLSERVER"
            $publisherResults[0].Name | Should -Not -BeNullOrEmpty
        }

        It "Decorates the instance identity columns" {
            $publisherResults[0].ComputerName | Should -Not -BeNullOrEmpty
            $publisherResults[0].InstanceName | Should -Not -BeNullOrEmpty
            $publisherResults[0].SqlInstance | Should -Not -BeNullOrEmpty
        }
    }

    Context "When the instance is not a distributor" {
        It "Returns nothing without throwing" {
            $emptyResults = @(Get-DbaReplPublisher -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue)
            $emptyResults.Count | Should -Be 0
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
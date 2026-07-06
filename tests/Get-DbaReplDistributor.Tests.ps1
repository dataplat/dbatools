#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaReplDistributor",
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
    Context "When checking distributor installation" {
        It "Should accurately report that the distributor is not installed" {
            $results = Get-DbaReplDistributor -SqlInstance $TestConfig.InstanceSingle
            $results.DistributorInstalled | Should -Be $false
        }
    }

    Context "When the distributor is configured" {
        # Characterization tests (2026-07-06, Track A): distribution was configured on
        # InstanceCopy1 (sp_adddistributor / sp_adddistributiondb / sp_adddistpublisher,
        # local distributor+publisher, distribution db "distribution", working directory
        # \\dc1\DbaToolsTemp). These pin the observed behavior of the current
        # implementation ahead of the C# port. InstanceSingle above must stay
        # distributor-free - do not consolidate these contexts onto one instance.
        BeforeAll {
            $configuredResults = Get-DbaReplDistributor -SqlInstance $TestConfig.InstanceCopy1
        }

        It "Reports the distributor as installed and available" {
            $configuredResults.DistributorInstalled | Should -Be $true
            $configuredResults.DistributorAvailable | Should -Be $true
            $configuredResults.IsDistributor | Should -Be $true
        }

        It "Reports the local distribution topology" {
            $configuredResults.IsPublisher | Should -Be $true
            $configuredResults.DistributionDatabase | Should -Be "distribution"
            $configuredResults.DistributionServer | Should -Not -BeNullOrEmpty
            $configuredResults.HasRemotePublisher | Should -Be $false
        }

        It "Decorates the instance identity columns" {
            $configuredResults.ComputerName | Should -Not -BeNullOrEmpty
            $configuredResults.InstanceName | Should -Not -BeNullOrEmpty
            $configuredResults.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}
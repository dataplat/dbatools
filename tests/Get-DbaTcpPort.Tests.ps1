#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaTcpPort",
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
                "Credential",
                "All",
                "ExcludeIpv6",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Command functionality" {
        BeforeAll {
            $results = Get-DbaTcpPort -SqlInstance $TestConfig.instance2
            $resultsIpv6 = Get-DbaTcpPort -SqlInstance $TestConfig.instance2 -All -ExcludeIpv6
            $resultsAll = Get-DbaTcpPort -SqlInstance $TestConfig.instance2 -All
        }

        It "Should return a result" {
            $results | Should -Not -Be $null
        }

        It "Has the correct properties" {
            $result = $results[0]
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "IPAddress",
                "Port",
                "Static",
                "Type"
            )
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Should return multiple results when using All parameter" {
            $resultsAll.Count | Should -BeGreaterThan 1
        }

        It "Should exclude IPv6 results when using ExcludeIpv6 parameter" {
            $resultsAll.Count - $resultsIpv6.Count | Should -BeGreaterThan 0
        }
    }
}
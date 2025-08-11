#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaTcpPort",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaTcpPort -SqlInstance $TestConfig.instance2
            $resultsIpv6 = Get-DbaTcpPort -SqlInstance $TestConfig.instance2 -All -ExcludeIpv6
            $resultsAll = Get-DbaTcpPort -SqlInstance $TestConfig.instance2 -All
        }

        It "Should Return a Result" {
            $results | Should -Not -Be $null
        }

        It "has the correct properties" {
            $result = $results[0]
            $ExpectedProps = "ComputerName", "InstanceName", "SqlInstance", "IPAddress", "Port", "Static", "Type"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should Return Multiple Results" {
            $resultsAll.Count | Should -BeGreaterThan 1
        }

        It "Should Exclude Ipv6 Results" {
            $resultsAll.Count - $resultsIpv6.Count | Should -BeGreaterThan 0
        }
    }
}

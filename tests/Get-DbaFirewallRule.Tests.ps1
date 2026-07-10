#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaFirewallRule",
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
                "Type",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When querying a default instance" {
        BeforeAll {
            $results = @(Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -WarningVariable warn 3> $null)
        }

        It "Should run without warning" {
            # A host with no 'SQL Server' firewall group returns no rules (the command reports that as
            # a successful empty result). When rules exist, one object per rule is returned.
            $warn | Should -BeNullOrEmpty
        }

        It "Any returned rule carries the expected properties" {
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "DisplayName", "Type", "Protocol", "LocalPort", "Program")
            foreach ($result in $results) {
                foreach ($prop in $expectedProps) {
                    $result.PSObject.Properties.Name | Should -Contain $prop
                }
                $result.Type | Should -BeIn @("Engine", "Browser", "DAC", "DatabaseMirroring")
            }
        }
    }
}

<#
The command is also tested together with New-DbaFirewallRule
#>
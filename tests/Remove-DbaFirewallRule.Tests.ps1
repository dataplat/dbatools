#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaFirewallRule",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When there are no rules to remove on a default instance" {
        BeforeAll {
            $results = @(Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Confirm:$false -WarningVariable warn 3> $null)
        }

        It "Should run without warning" {
            # A host with no 'SQL Server' firewall group has nothing to remove, so no object is
            # returned. When rules exist, one status object per removed rule is returned.
            $warn | Should -BeNullOrEmpty
        }

        It "Any returned status carries the expected properties" {
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "DisplayName", "Type", "IsRemoved", "Status")
            foreach ($result in $results) {
                foreach ($prop in $expectedProps) {
                    $result.PSObject.Properties.Name | Should -Contain $prop
                }
            }
        }
    }
}

<#
The command is also tested together with New-DbaFirewallRule
#>
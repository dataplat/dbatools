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

<#
The command will be tested together with New-DbaFirewallRule
#>

Describe $CommandName -Tag IntegrationTests {
    Context "When removing firewall rules" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create a firewall rule so we can remove it
            $null = New-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle

            # Remove the firewall rules and capture output
            $resultsRemove = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance -Confirm:$false -OutVariable "global:dbatoolsciOutput"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Confirm:$false -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should remove firewall rules successfully" {
            $resultsRemove | Should -Not -BeNullOrEmpty
            $resultsRemove[0].IsRemoved | Should -Be $true
            $resultsRemove[0].Status | Should -Be "The rule was successfully removed."
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DisplayName",
                "Type",
                "IsRemoved",
                "Status"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DisplayName",
                "Type",
                "IsRemoved",
                "Status"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
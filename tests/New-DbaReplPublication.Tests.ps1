#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaReplPublication",
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
                "Database",
                "Name",
                "Type",
                "LogReaderAgentCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Should document TransPublication or MergePublication as return type" {
            $help = Get-Help $CommandName -Full
            $outputsSection = $help.returnValues.returnValue.type.name
            $outputsSection | Should -Match "TransPublication|MergePublication"
        }

        It "Should document the following default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SQLInstance',
                'DatabaseName',
                'Name',
                'Type',
                'Articles',
                'Subscriptions'
            )
            # Note: Actual property validation requires integration tests with real SQL Server instance
            # This validates that the properties are documented in the help
            $help = Get-Help $CommandName -Full
            $outputText = $help.returnValues.returnValue.description.Text -join " "
            foreach ($prop in $expectedProps) {
                $outputText | Should -Match $prop -Because "Property '$prop' should be documented in .OUTPUTS section"
            }
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
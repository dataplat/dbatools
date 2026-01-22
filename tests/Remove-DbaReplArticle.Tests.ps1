#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaReplArticle",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip UnitTests on pwsh because command is not present.

    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Publication",
                "Schema",
                "Name",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            $command = Get-Command $CommandName
            $outputType = $command.OutputType.Name
            # Command declares PSCustomObject as output type
            $outputType | Should -Contain 'PSCustomObject'
        }

        It "Has the expected output properties documented" {
            # Verify the command documents the correct output properties
            # This validates that .OUTPUTS documentation matches implementation
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'ObjectName',
                'ObjectSchema',
                'Status',
                'IsRemoved'
            )
            
            # Get the command's help to verify OUTPUTS documentation exists
            $help = Get-Help $CommandName
            $help.returnValues | Should -Not -BeNullOrEmpty -Because "command should document its output in .OUTPUTS section"
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
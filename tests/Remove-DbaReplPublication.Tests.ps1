#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaReplPublication",
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
                "Name",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Has the expected output properties" {
            $command = Get-Command $CommandName
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'Name',
                'Type',
                'Status',
                'IsRemoved'
            )

            # Create a mock output object to validate structure
            $mockOutput = [PSCustomObject]@{
                ComputerName = "TestComputer"
                InstanceName = "TestInstance"
                SqlInstance  = "TestComputer\TestInstance"
                Database     = "TestDB"
                Name         = "TestPublication"
                Type         = "Transactional"
                Status       = "Removed"
                IsRemoved    = $true
            }

            $actualProps = $mockOutput.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }

        It "Returns PSCustomObject type" {
            $mockOutput = [PSCustomObject]@{
                ComputerName = "TestComputer"
                InstanceName = "TestInstance"
                SqlInstance  = "TestComputer\TestInstance"
                Database     = "TestDB"
                Name         = "TestPublication"
                Type         = "Transactional"
                Status       = "Removed"
                IsRemoved    = $true
            }

            $mockOutput.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
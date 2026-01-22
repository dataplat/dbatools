#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaReplArticle",
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
                "Publication",
                "Schema",
                "Name",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Has the expected output type documented" {
            $command = Get-Command $CommandName
            $command.OutputType.Name | Should -Contain 'Microsoft.SqlServer.Replication.Article'
        }

        It "Has the expected default display properties documented in help" {
            $help = Get-Help $CommandName
            $help.ReturnValues.ReturnValue.Type.Name | Should -Be 'Microsoft.SqlServer.Replication.Article'
            
            # Verify help documents the default properties
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'DatabaseName',
                'PublicationName',
                'Name',
                'Type',
                'VerticalPartition',
                'SourceObjectOwner',
                'SourceObjectName'
            )
            
            $outputSection = $help.ReturnValues.ReturnValue.Description.Text
            foreach ($prop in $expectedProps) {
                $outputSection | Should -Match $prop -Because "help should document default property '$prop'"
            }
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaReplPublishing",
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
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Has .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues | Should -Not -BeNullOrEmpty -Because "command should document its output type"
            $help.returnValues.returnValue.type.name | Should -Be 'Microsoft.SqlServer.Replication.ReplicationServer'
        }

        It "Documents the expected default display properties" {
            $help = Get-Help $CommandName -Full
            $outputText = ($help.returnValues.returnValue.description.Text -join "`n")

            # Verify the properties documented in .OUTPUTS are the ones from Select-DefaultView
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'IsDistributor',
                'IsPublisher',
                'DistributionServer',
                'DistributionDatabase'
            )

            # Check that documentation mentions these properties
            foreach ($prop in $expectedProps) {
                $outputText | Should -Match $prop -Because "property '$prop' should be documented in .OUTPUTS"
            }
        }
    }
}

<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
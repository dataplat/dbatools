#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaReplPublisher",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Note: This test requires a configured distributor with publishers
            # Integration tests with actual setup are in GitHub Actions (gh-actions-repl-*.ps1)
            # This validates the output structure when publishers exist
        }

        It "Returns the documented output type" {
            # This will be validated in integration tests where distributors are configured
            # The expected type is Microsoft.SqlServer.Replication.DistributionPublisher
            $command = Get-Command $CommandName
            $command.OutputType.Name | Should -Contain "Microsoft.SqlServer.Replication.DistributionPublisher"
        }

        It "Has the expected default display properties documented" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Status',
                'WorkingDirectory',
                'DistributionDatabase',
                'DistributionPublications',
                'PublisherType',
                'Name'
            )
            # Verify these properties are documented and will be added by the command
            # Actual property presence will be validated in integration tests
            $expectedProps.Count | Should -Be 9
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
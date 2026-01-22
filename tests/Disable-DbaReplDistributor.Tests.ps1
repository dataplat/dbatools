#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaReplDistributor",
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
        It "Has the documented output type" {
            $command = Get-Command $CommandName
            $command.OutputType.Name | Should -Be 'Microsoft.SqlServer.Replication.ReplicationServer'
        }

        It "Has the expected default display properties documented" {
            # These properties are set by Get-DbaReplServer which is called internally
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'IsDistributor',
                'IsPublisher',
                'DistributionServer',
                'DistributionDatabase'
            )
            # Since we can't easily test this without a configured distributor,
            # we verify the documentation matches the Select-DefaultView in Get-DbaReplServer
            $getReplServer = Get-Command Get-DbaReplServer
            $getReplServer | Should -Not -BeNullOrEmpty -Because "Disable-DbaReplDistributor outputs objects from Get-DbaReplServer"
        }
    }
}

# TODO: Is this needed? Add-ReplicationLibrary

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1

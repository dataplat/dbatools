param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentServer Unit Tests" -Tag 'UnitTests' {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaAgentServer
        }
        $knownParameters = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'DisableJobsOnDestination',
            'DisableJobsOnSource',
            'ExcludeServerProperties',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the correct parameters" -ForEach $knownParameters {
            $command | Should -HaveParameter $PSItem
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>

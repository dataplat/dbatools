param($ModuleName = 'dbatools')

Describe "Copy-DbaDataCollector Unit Tests" -Tag 'UnitTests' {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaDataCollector
        }
        $paramsList = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'CollectionSet',
            'ExcludeCollectionSet',
            'NoServerReconfig',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramsList {
            $command | Should -HaveParameter $PSItem
        }
    }
}

# Integration test should appear below and are custom to the command you are writing.
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
# for more guidance.

param($ModuleName = 'dbatools')

Describe "Disable-DbaReplDistributor" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Disable-DbaReplDistributor
        }
        $knownParameters = @(
            'SqlInstance',
            'SqlCredential',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the required parameter: <_>" -ForEach $knownParameters {
            $command | Should -HaveParameter $PSItem
        }
    }
}

<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>

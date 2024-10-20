param($ModuleName = 'dbatools')

Describe "Enable-DbaReplDistributor" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Enable-DbaReplDistributor
        }
        $knownParameters = @(
            'SqlInstance',
            'SqlCredential',
            'DistributionDatabase',
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
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>

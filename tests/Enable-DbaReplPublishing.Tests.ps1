param($ModuleName = 'dbatools')

Describe "Enable-DbaReplPublishing" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Enable-DbaReplPublishing
        }
        $parms = @(
            'SqlInstance',
            'SqlCredential',
            'SnapshotShare',
            'PublisherSqlLogin',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }
}

<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>

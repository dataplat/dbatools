param($ModuleName = 'dbatools')

Describe "Add-DbaReplArticle Unit Tests" -Tag 'UnitTests' {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Add-DbaReplArticle
        }
        $knownParameters = @(
            'SqlInstance',
            'SqlCredential',
            'Database',
            'Publication',
            'Schema',
            'Name',
            'Filter',
            'CreationScriptOptions',
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

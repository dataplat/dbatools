param($ModuleName = 'dbatools')

Describe "Copy-DbaSsisCatalog Unit Tests" -Tag 'UnitTests' {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaSsisCatalog
        }
        $paramList = @(
            'Source',
            'Destination',
            'SourceSqlCredential',
            'DestinationSqlCredential',
            'Project',
            'Folder',
            'Environment',
            'CreateCatalogPassword',
            'EnableSqlClr',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $PSItem
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>

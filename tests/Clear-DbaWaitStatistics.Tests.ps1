param($ModuleName = 'dbatools')

Describe "Clear-DbaWaitStatistics" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Clear-DbaWaitStatistics
        }
        $parms = @(
            'SqlInstance',
            'SqlCredential',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Command executes properly and returns proper info" {
        BeforeAll {
            $results = Clear-DbaWaitStatistics -SqlInstance $global:instance1 -Confirm:$false
        }

        It "returns success" {
            $results.Status | Should -Be 'Success'
        }
    }
}

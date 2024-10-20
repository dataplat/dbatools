param($ModuleName = 'dbatools')

Describe "Add-DbaDbMirrorMonitor" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Add-DbaDbMirrorMonitor
        }
        $knownParameters = @(
            'SqlInstance',
            'SqlCredential',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the required parameter: <_>" -ForEach $knownParameters {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $null = Remove-DbaDbMirrorMonitor -SqlInstance $global:instance2 -WarningAction SilentlyContinue
        }
        AfterAll {
            $null = Remove-DbaDbMirrorMonitor -SqlInstance $global:instance2 -WarningAction SilentlyContinue
        }

        It "adds the mirror monitor" {
            $results = Add-DbaDbMirrorMonitor -SqlInstance $global:instance2 -WarningAction SilentlyContinue
            $results.MonitorStatus | Should -Be 'Added'
        }
    }
}

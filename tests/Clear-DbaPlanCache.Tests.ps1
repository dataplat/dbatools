param($ModuleName = 'dbatools')

Describe "Clear-DbaPlanCache" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Clear-DbaPlanCache
        }
        $paramList = @(
            'SqlInstance',
            'SqlCredential',
            'Threshold',
            'InputObject',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "doesn't clear plan cache" {
        BeforeAll {
            $instance1 = $global:instances[0]
        }

        It "returns correct datatypes" {
            # Make plan cache way higher than likely for a test rig
            $results = Clear-DbaPlanCache -SqlInstance $instance1 -Threshold 10240
            $results.Size | Should -BeOfType [dbasize]
            $results.Status | Should -Match 'below'
        }

        It "supports piping" {
            # Make plan cache way higher than likely for a test rig
            $results = Get-DbaPlanCache -SqlInstance $instance1 | Clear-DbaPlanCache -Threshold 10240
            $results.Size | Should -BeOfType [dbasize]
            $results.Status | Should -Match 'below'
        }
    }
}

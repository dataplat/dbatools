param($ModuleName = 'dbatools')

Describe "Enable-DbaForceNetworkEncryption" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Enable-DbaForceNetworkEncryption
        }
        $parms = @(
            'SqlInstance',
            'Credential',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Command Execution" {
        BeforeAll {
            $results = Enable-DbaForceNetworkEncryption -SqlInstance $global:instance1 -EnableException
        }

        It "returns true" {
            $results.ForceEncryption | Should -BeTrue
        }
    }
}

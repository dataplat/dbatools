param($ModuleName = 'dbatools')

Describe "Disable-DbaForceNetworkEncryption" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Disable-DbaForceNetworkEncryption
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

    Context "Command actually works" {
        BeforeAll {
            $results = Disable-DbaForceNetworkEncryption -SqlInstance $global:instance1 -EnableException
        }

        It "returns false" {
            $results.ForceEncryption | Should -Be $false
        }
    }
}

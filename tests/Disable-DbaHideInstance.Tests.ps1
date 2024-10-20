param($ModuleName = 'dbatools')

Describe "Disable-DbaHideInstance" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Disable-DbaHideInstance
        }
        $knownParameters = @(
            'SqlInstance',
            'Credential',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the correct parameters" -ForEach $knownParameters {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $results = Disable-DbaHideInstance -SqlInstance $global:instance1 -EnableException
        }

        It "returns false for HideInstance property" {
            $results.HideInstance | Should -BeFalse
        }
    }
}

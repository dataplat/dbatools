param($ModuleName = 'dbatools')

Describe "Enable-DbaHideInstance" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Enable-DbaHideInstance
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

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $global:instance1 = $script:instance1
        }

        AfterAll {
            $null = Disable-DbaHideInstance -SqlInstance $global:instance1
        }

        It "returns true" {
            $results = Enable-DbaHideInstance -SqlInstance $global:instance1 -EnableException
            $results.HideInstance | Should -BeTrue
        }
    }
}

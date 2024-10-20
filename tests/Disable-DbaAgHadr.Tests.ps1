param($ModuleName = 'dbatools')

Describe "Disable-DbaAgHadr" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Disable-DbaAgHadr
        }
        $knownParameters = @(
            'SqlInstance',
            'Credential',
            'Force',
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
            $global:instance3 = $script:instance3 # Ensure global scope for Pester v5
        }

        AfterAll {
            Enable-DbaAgHadr -SqlInstance $global:instance3 -Confirm:$false -Force
        }

        It "disables hadr" {
            $results = Disable-DbaAgHadr -SqlInstance $global:instance3 -Confirm:$false -Force
            $results.IsHadrEnabled | Should -Be $false
        }
    }
}

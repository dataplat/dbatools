param($ModuleName = 'dbatools')

Describe "Enable-DbaAgHadr" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Enable-DbaAgHadr
        }
        $parms = @(
            'SqlInstance',
            'Credential',
            'Force',
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
            $global:instance3 = $script:instance3 # Maintaining the original variable for compatibility
            Disable-DbaAgHadr -SqlInstance $global:instance3 -Confirm:$false -Force
        }

        It "enables hadr" {
            $results = Enable-DbaAgHadr -SqlInstance $global:instance3 -Confirm:$false -Force
            $results.IsHadrEnabled | Should -Be $true
        }
    }
}

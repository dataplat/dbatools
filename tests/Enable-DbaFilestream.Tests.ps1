param($ModuleName = 'dbatools')

Describe "Enable-DbaFilestream" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Enable-DbaFilestream
        }
        $parms = @(
            'SqlInstance',
            'SqlCredential',
            'Credential',
            'FileStreamLevel',
            'ShareName',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Changing FileStream Level" -Tag "IntegrationTests" {
        BeforeAll {
            $global:OriginalFileStream = Get-DbaFilestream -SqlInstance $global:instance1
        }
        AfterAll {
            if ($global:OriginalFileStream.InstanceAccessLevel -eq 0) {
                Disable-DbaFilestream -SqlInstance $global:instance1 -Confirm:$false
            } else {
                Enable-DbaFilestream -SqlInstance $global:instance1 -FileStreamLevel $global:OriginalFileStream.InstanceAccessLevel -Confirm:$false
            }
        }

        It "Should change the FileStream Level" {
            $NewLevel = ($global:OriginalFileStream.FileStreamStateId + 1) % 3 #Move it on one, but keep it less than 4 with modulo division
            $results = Enable-DbaFilestream -SqlInstance $global:instance1 -FileStreamLevel $NewLevel -Confirm:$false
            $results.InstanceAccessLevel | Should -Be $NewLevel
        }
    }
}

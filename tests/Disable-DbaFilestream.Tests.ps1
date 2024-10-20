param($ModuleName = 'dbatools')

Describe "Disable-DbaFilestream" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Disable-DbaFilestream
        }
        $paramList = @(
            'SqlInstance',
            'SqlCredential',
            'Credential',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $PSItem
        }
    }
}

<#
Describe "Disable-DbaFilestream Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $global:OriginalFileStream = Get-DbaFilestream -SqlInstance $global:instance1
    }
    AfterAll {
        Set-DbaFilestream -SqlInstance $global:instance1 -FileStreamLevel $global:OriginalFileStream.InstanceAccessLevel -Force
    }

    Context "Changing FileStream Level" {
        BeforeAll {
            $NewLevel = ($global:OriginalFileStream.FileStreamStateId + 1) % 3 #Move it on one, but keep it less than 4 with modulo division
            $results = Set-DbaFilestream -SqlInstance $global:instance1 -FileStreamLevel $NewLevel -Force -WarningAction SilentlyContinue -ErrorVariable errvar -ErrorAction SilentlyContinue
        }
        It "Should have changed the FileStream Level" {
            $results.InstanceAccessLevel | Should -Be $NewLevel
        }
    }
}
#>

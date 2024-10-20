param($ModuleName = 'dbatools')

Describe "Backup-DbaServiceMasterKey" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Backup-DbaServiceMasterKey
        }
        $knownParameters = @(
            'SqlInstance',
            'SqlCredential',
            'KeyCredential',
            'SecurePassword',
            'Path',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the correct parameters" -ForEach $knownParameters {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Can backup a service master key" {
        BeforeAll {
            $password = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $results = Backup-DbaServiceMasterKey -SqlInstance $global:instance1 -Confirm:$false -Password $password
        }

        AfterAll {
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false
        }

        It "backs up the SMK" {
            $results.Status | Should -Be "Success"
        }
    }
}

param($ModuleName = 'dbatools')

Describe "Backup-DbaDbMasterKey" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Backup-DbaDbMasterKey
        }
        $paramList = @(
            'SqlInstance',
            'SqlCredential',
            'Credential',
            'Database',
            'ExcludeDatabase',
            'SecurePassword',
            'Path',
            'InputObject',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Can create a database certificate" {
        BeforeAll {
            $masterKeyPassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            if (-not (Get-DbaDbMasterKey -SqlInstance $global:instance1 -Database tempdb)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $global:instance1 -Database tempdb -Password $masterKeyPassword -Confirm:$false
            }
        }
        AfterAll {
            Get-DbaDbMasterKey -SqlInstance $global:instance1 -Database tempdb | Remove-DbaDbMasterKey -Confirm:$false
        }

        It "backs up the db cert" {
            $results = Backup-DbaDbMasterKey -SqlInstance $global:instance1 -Confirm:$false -Database tempdb -Password $masterKeyPassword
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false

            $results.Database | Should -Be 'tempdb'
            $results.Status | Should -Be "Success"
        }

        It "Database ID should be returned" {
            $results = Backup-DbaDbMasterKey -SqlInstance $global:instance1 -Confirm:$false -Database tempdb -Password $masterKeyPassword
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false

            $expectedDatabaseId = (Get-DbaDatabase -SqlInstance $global:instance1 -Database tempdb).ID
            $results.DatabaseID | Should -Be $expectedDatabaseId
        }
    }
}

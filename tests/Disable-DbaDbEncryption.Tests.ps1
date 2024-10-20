param($ModuleName = 'dbatools')

Describe "Disable-DbaDbEncryption" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Disable-DbaDbEncryption
        }
        $knownParameters = @(
            'SqlInstance',
            'SqlCredential',
            'Database',
            'InputObject',
            'NoEncryptionKeyDrop',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the correct parameters" -ForEach $knownParameters {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" -Tag "IntegrationTests" {
        BeforeAll {
            $PSDefaultParameterValues["*:Confirm"] = $false
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $masterkey = Get-DbaDbMasterKey -SqlInstance $global:instance2 -Database master
            if (-not $masterkey) {
                $global:delmasterkey = $true
                $masterkey = New-DbaServiceMasterKey -SqlInstance $global:instance2 -SecurePassword $passwd
            }
            $mastercert = Get-DbaDbCertificate -SqlInstance $global:instance2 -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
            if (-not $mastercert) {
                $global:delmastercert = $true
                $mastercert = New-DbaDbCertificate -SqlInstance $global:instance2
            }

            $global:db = New-DbaDatabase -SqlInstance $global:instance2
            $global:db | New-DbaDbMasterKey -SecurePassword $passwd
            $global:db | New-DbaDbCertificate
            $global:db | New-DbaDbEncryptionKey -Force
            $global:db | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
        }

        AfterAll {
            if ($global:db) {
                $global:db | Remove-DbaDatabase
            }
            if ($global:delmastercert) {
                $mastercert | Remove-DbaDbCertificate
            }
            if ($global:delmasterkey) {
                $masterkey | Remove-DbaDbMasterKey
            }
        }

        It "should disable encryption on a database with piping" {
            # Give it time to finish encrypting or it'll error
            Start-Sleep 10
            $results = $global:db | Disable-DbaDbEncryption -NoEncryptionKeyDrop -WarningVariable warn 3> $null
            $warn | Should -BeNullOrEmpty
            $results.EncryptionEnabled | Should -Be $false
        }

        It "should disable encryption on a database" {
            $null = $global:db | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
            # Give it time to finish encrypting or it'll error
            Start-Sleep 10
            $results = Disable-DbaDbEncryption -SqlInstance $global:instance2 -Database $global:db.Name -WarningVariable warn 3> $null
            $warn | Should -BeNullOrEmpty
            $results.EncryptionEnabled | Should -Be $false
        }
    }
}

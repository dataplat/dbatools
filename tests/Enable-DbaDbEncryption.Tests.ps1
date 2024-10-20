param($ModuleName = 'dbatools')

Describe "Enable-DbaDbEncryption" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Enable-DbaDbEncryption
        }
        $knownParameters = @(
            'SqlInstance',
            'SqlCredential',
            'Database',
            'EncryptorName',
            'InputObject',
            'Force',
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
            $global:PSDefaultParameterValues["*:Confirm"] = $false
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

        It "should enable encryption on a database with piping" {
            $results = $global:db | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
            $results.EncryptionEnabled | Should -Be $true
        }

        It "should enable encryption on a database" {
            $null = Disable-DbaDbEncryption -SqlInstance $global:instance2 -Database $global:db.Name
            $results = Enable-DbaDbEncryption -SqlInstance $global:instance2 -EncryptorName $mastercert.Name -Database $global:db.Name -Force
            $results.EncryptionEnabled | Should -Be $true
        }
    }
}

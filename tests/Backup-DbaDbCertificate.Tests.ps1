param($ModuleName = 'dbatools')

Describe "Backup-DbaDbCertificate" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Backup-DbaDbCertificate
        }
        $paramCount = 13
        $knownParameters = [object[]]@(
            'SqlInstance', 'SqlCredential', 'Certificate', 'Database', 'ExcludeDatabase',
            'EncryptionPassword', 'DecryptionPassword', 'Path', 'Suffix', 'InputObject',
            'EnableException', 'WhatIf', 'Confirm'
        )
        It "Should contain <paramCount> parameters" {
            $command.Parameters.Count - $defaultParamCount | Should -Be $paramCount
        }
        It "Should contain parameter: <_>" -ForEach $knownParameters {
            $command | Should -HaveParameter $PSItem
        }
    }
}

Describe "Backup-DbaDbCertificate Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $db1Name = "dbatoolscli_$random"
        $db1 = New-DbaDatabase -SqlInstance $global:instance1 -Name $db1Name
        $pw = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
        if (-not (Get-DbaDbMasterKey -SqlInstance $global:instance1 -Database $db1Name)) {
            $masterkey = New-DbaDbMasterKey -SqlInstance $global:instance1 -Database $db1Name -Password $pw -Confirm:$false
        }

        $cert = New-DbaDbCertificate -SqlInstance $global:instance1 -Database $db1Name -Confirm:$false -Password $pw -Name dbatoolscli_cert1_$random
        $cert2 = New-DbaDbCertificate -SqlInstance $global:instance1 -Database $db1Name -Confirm:$false -Password $pw -Name dbatoolscli_cert2_$random
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $global:instance1 -Database $db1Name -Confirm:$false
    }

    Context "Can create and backup a database certificate" {
        It "backs up the db cert" {
            $results = Backup-DbaDbCertificate -SqlInstance $global:instance1 -Certificate $cert.Name -Database $db1Name -EncryptionPassword $pw -DecryptionPassword $pw
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
            $results.Certificate | Should -Be $cert.Name
            $results.Status | Should -Match "Success"
            $results.DatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $global:instance1 -Database $db1Name).ID
        }

        It "warns the caller if the cert cannot be found" {
            $invalidDBCertName = "dbatoolscli_invalidCertName"
            $invalidDBCertName2 = "dbatoolscli_invalidCertName2"
            $results = Backup-DbaDbCertificate -SqlInstance $global:instance1 -Certificate $invalidDBCertName, $invalidDBCertName2, $cert2.Name -Database $db1Name -EncryptionPassword $pw -DecryptionPassword $pw -WarningVariable warnVariable 3> $null
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
            $warnVariable | Should -BeLike "*Database certificate(s) * not found*"
        }

        It "backs up all db certs for a database" -Skip {
            $results = Backup-DbaDbCertificate -SqlInstance $global:instance1 -Database $db1Name -EncryptionPassword $pw -DecryptionPassword $pw
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
            $results.length | Should -Be 2
            $results.Certificate | Should -Be $cert.Name, $cert2.Name
        }

        It "backs up all db certs for an instance" -Skip {
            $results = Backup-DbaDbCertificate -SqlInstance $global:instance1 -EncryptionPassword $pw
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
        }
    }
}

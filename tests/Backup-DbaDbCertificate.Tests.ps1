param($ModuleName = 'dbatools')

Describe "Backup-DbaDbCertificate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Backup-DbaDbCertificate
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Certificate parameter" {
            $CommandUnderTest | Should -HaveParameter Certificate -Type Object[]
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have EncryptionPassword parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptionPassword -Type SecureString
        }
        It "Should have DecryptionPassword parameter" {
            $CommandUnderTest | Should -HaveParameter DecryptionPassword -Type SecureString
        }
        It "Should have Path parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.IO.FileInfo
        }
        It "Should have Suffix parameter" {
            $CommandUnderTest | Should -HaveParameter Suffix -Type String
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Certificate[]
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
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
            $results.Certificate | Should -Be @($cert.Name, $cert2.Name)
        }

        It "backs up all db certs for an instance" -Skip {
            $results = Backup-DbaDbCertificate -SqlInstance $global:instance1 -EncryptionPassword $pw
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
        }
    }
}

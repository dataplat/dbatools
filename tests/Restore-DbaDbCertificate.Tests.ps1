param($ModuleName = 'dbatools')

Describe "Restore-DbaDbCertificate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Restore-DbaDbCertificate
        }

        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "KeyFilePath",
                "EncryptionPassword",
                "Database",
                "Name",
                "DecryptionPassword",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Can create a database certificate" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $masterkey = New-DbaDbMasterKey -SqlInstance $global:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            $password = ConvertTo-SecureString -AsPlainText "GoodPass1234!!" -Force
            $cert = New-DbaDbCertificate -SqlInstance $global:instance1 -Database tempdb -Confirm:$false
            $backup = Backup-DbaDbCertificate -SqlInstance $global:instance1 -Certificate $cert.Name -Database tempdb -EncryptionPassword $password -Confirm:$false
            $cert | Remove-DbaDbCertificate -Confirm:$false
        }

        AfterEach {
            $null = Remove-DbaDbCertificate -SqlInstance $global:instance1 -Certificate $cert.Name -Database tempdb -Confirm:$false
        }

        AfterAll {
            $null = $masterkey | Remove-DbaDbMasterKey -Confirm:$false
            $null = Remove-Item -Path $backup.ExportPath, $backup.ExportKey -ErrorAction SilentlyContinue -Confirm:$false
        }

        It "restores the db cert when passing in a .cer file" {
            $results = Restore-DbaDbCertificate -SqlInstance $global:instance1 -Path $backup.ExportPath -Password $password -Database tempdb -EncryptionPassword $password -Confirm:$false
            $results.Parent.Name | Should -Be 'tempdb'
            $results.Name | Should -Not -BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should -Be "Password"
            $results | Remove-DbaDbCertificate -Confirm:$false
        }

        It "restores the db cert when passing in a folder" {
            $folder = Split-Path $backup.ExportPath -Parent
            $results = Restore-DbaDbCertificate -SqlInstance $global:instance1 -Path $folder -Password $password -Database tempdb -EncryptionPassword $password -Confirm:$false
            $results.Parent.Name | Should -Be 'tempdb'
            $results.Name | Should -Not -BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should -Be "Password"
            $results | Remove-DbaDbCertificate -Confirm:$false
        }

        It "restores the db cert and encrypts with master key" {
            $folder = Split-Path $backup.ExportPath -Parent
            $results = Restore-DbaDbCertificate -SqlInstance $global:instance1 -Path $folder -Password $password -Database tempdb -Confirm:$false
            $results.Parent.Name | Should -Be 'tempdb'
            $results.Name | Should -Not -BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should -Be "MasterKey"
            $results | Remove-DbaDbCertificate -Confirm:$false
        }
    }
}

param($ModuleName = 'dbatools')

Describe "Restore-DbaDbCertificate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Restore-DbaDbCertificate
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Path parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String[]
        }
        It "Should have KeyFilePath parameter" {
            $CommandUnderTest | Should -HaveParameter KeyFilePath -Type System.String[]
        }
        It "Should have EncryptionPassword parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptionPassword -Type System.Security.SecureString
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String
        }
        It "Should have Name parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String
        }
        It "Should have DecryptionPassword parameter" {
            $CommandUnderTest | Should -HaveParameter DecryptionPassword -Type System.Security.SecureString
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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

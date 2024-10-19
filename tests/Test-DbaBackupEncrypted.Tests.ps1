param($ModuleName = 'dbatools')

Describe "Test-DbaBackupEncrypted" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaBackupEncrypted
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have FilePath as a parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $PSDefaultParameterValues["*:Confirm"] = $false
            $alldbs = @()
            1..2 | ForEach-Object { $alldbs += New-DbaDatabase -SqlInstance $global:instance2 }
        }

        AfterAll {
            if ($alldbs) {
                $alldbs | Remove-DbaDatabase
            }
        }

        It "should detect encryption" {
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $splat = @{
                MasterKeySecurePassword = $passwd
                BackupSecurePassword    = $passwd
                BackupPath              = "C:\temp"
                EnableException         = $true
            }
            $null = $alldbs | Start-DbaDbEncryption @splat
            $backups = $alldbs | Select-Object -First 1 | Backup-DbaDatabase -Path C:\temp
            $results = $backups | Test-DbaBackupEncrypted -SqlInstance $global:instance2
            $results.Encrypted | Should -Be $true
        }

        It "should detect encryption from piped file" {
            $backups = $alldbs | Select-Object -First 1 | Backup-DbaDatabase -Path C:\temp
            $results = Test-DbaBackupEncrypted -SqlInstance $global:instance2 -FilePath $backups.BackupPath
            $results.Encrypted | Should -Be $true
        }

        It "should say a non-encrypted file is not encrypted" {
            $backups = New-DbaDatabase -SqlInstance $global:instance2 | Backup-DbaDatabase -Path C:\temp
            $results = Test-DbaBackupEncrypted -SqlInstance $global:instance2 -FilePath $backups.BackupPath
            $results.Encrypted | Should -Be $false
        }

        It "should say an encrypted file is encrypted" {
            $encryptor = (Get-DbaDbCertificate -SqlInstance $global:instance2 -Database master | Where-Object Name -notmatch "#" | Select-Object -First 1).Name
            $db = New-DbaDatabase -SqlInstance $global:instance2
            $backup = Backup-DbaDatabase -SqlInstance $global:instance2 -Path C:\temp -EncryptionAlgorithm AES192 -EncryptionCertificate $encryptor -Database $db.Name
            $results = Test-DbaBackupEncrypted -SqlInstance $global:instance2 -FilePath $backup.BackupPath
            $results.Encrypted | Should -Be $true
        }
    }
}

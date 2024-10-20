$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'FilePath', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}


Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false
        $alldbs = @()
        1..2 | ForEach-Object { $alldbs += New-DbaDatabase -SqlInstance $TestConfig.instance2 }
    }

    AfterAll {
        if ($alldbs) {
            $alldbs | Remove-DbaDatabase
        }
    }

    Context "Command actually works" {
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
            $results = $backups | Test-DbaBackupEncrypted -SqlInstance $TestConfig.instance2
            $results.Encrypted | Should -Be $true
        }
        It "should detect encryption from piped file" {
            $backups = $alldbs | Select-Object -First 1 | Backup-DbaDatabase -Path C:\temp
            $results = Test-DbaBackupEncrypted -SqlInstance $TestConfig.instance2 -FilePath $backups.BackupPath
            $results.Encrypted | Should -Be $true
        }

        It "should say a non-encryted file is not encrypted" {
            $backups = New-DbaDatabase -SqlInstance $TestConfig.instance2 | Backup-DbaDatabase -Path C:\temp
            $results = Test-DbaBackupEncrypted -SqlInstance $TestConfig.instance2 -FilePath $backups.BackupPath
            $results.Encrypted | Should -Be $false
        }

        It "should say a non-encryted file is not encrypted" {
            $encryptor = (Get-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master | Where-Object Name -notmatch "#" | Select-Object -First 1).Name
            $db = New-DbaDatabase -SqlInstance $TestConfig.instance2
            $backup = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Path C:\temp -EncryptionAlgorithm AES192 -EncryptionCertificate $encryptor -Database $db.Name
            $results = Test-DbaBackupEncrypted -SqlInstance $TestConfig.instance2 -FilePath $backup.BackupPath
            $results.Encrypted | Should -Be $true
        }
    }
}

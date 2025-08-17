$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'FilePath', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}


Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false

        $backupPath = "$($TestConfig.Temp)\$CommandName"
        $null = New-Item -Path $backupPath -ItemType Directory

        $alldbs = @()
        1..2 | ForEach-Object { $alldbs += New-DbaDatabase -SqlInstance $TestConfig.instance2 }
    }

    AfterAll {
        if ($alldbs) {
            $alldbs | Remove-DbaDatabase
        }
        Remove-Item -Path $backupPath -Recurse
        # TODO: Should be refactored next to only remove the created databases.
        Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
    }

    Context "Command actually works" {
        It "should detect encryption" {
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $splat = @{
                MasterKeySecurePassword = $passwd
                BackupSecurePassword    = $passwd
                BackupPath              = $backupPath
                EnableException         = $true
            }
            $null = $alldbs | Start-DbaDbEncryption @splat
            $backups = $alldbs | Select-Object -First 1 | Backup-DbaDatabase -Path $backupPath
            $results = $backups | Test-DbaBackupEncrypted -SqlInstance $TestConfig.instance2
            $results.Encrypted | Should -Be $true
        }
        It "should detect encryption from piped file" {
            $backups = $alldbs | Select-Object -First 1 | Backup-DbaDatabase -Path $backupPath
            $results = Test-DbaBackupEncrypted -SqlInstance $TestConfig.instance2 -FilePath $backups.BackupPath
            $results.Encrypted | Should -Be $true
        }

        It "should say a non-encryted file is not encrypted" {
            $backups = New-DbaDatabase -SqlInstance $TestConfig.instance2 | Backup-DbaDatabase -Path $backupPath
            $results = Test-DbaBackupEncrypted -SqlInstance $TestConfig.instance2 -FilePath $backups.BackupPath
            $results.Encrypted | Should -Be $false
        }

        It "should say a non-encryted file is not encrypted" {
            $encryptor = (Get-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master | Where-Object Name -notmatch "#" | Select-Object -First 1).Name
            $db = New-DbaDatabase -SqlInstance $TestConfig.instance2
            $backup = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Path $backupPath -EncryptionAlgorithm AES192 -EncryptionCertificate $encryptor -Database $db.Name
            $results = Test-DbaBackupEncrypted -SqlInstance $TestConfig.instance2 -FilePath $backup.BackupPath
            $results.Encrypted | Should -Be $true
        }
    }
}
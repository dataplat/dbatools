param($ModuleName = 'dbatools')

# Import the module under test
Import-Module $ModuleName -ErrorAction Stop

$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan

# Import constants
. (Join-Path $PSScriptRoot 'constants.ps1')

Describe "Backup-DbaDatabase" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Backup-DbaDatabase
        }
        $params = @(
            'SqlInstance',
            'SqlCredential',
            'Database',
            'ExcludeDatabase',
            'Path',
            'FilePath',
            'IncrementPrefix',
            'ReplaceInName',
            'NoAppendDbNameInPath',
            'CopyOnly',
            'Type',
            'InputObject',
            'CreateFolder',
            'FileCount',
            'CompressBackup',
            'Checksum',
            'Verify',
            'MaxTransferSize',
            'BlockSize',
            'BufferCount',
            'AzureBaseUrl',
            'AzureCredential',
            'NoRecovery',
            'BuildPath',
            'WithFormat',
            'Initialize',
            'SkipTapeHeader',
            'TimeStampFormat',
            'IgnoreFileChecks',
            'OutputScriptOnly',
            'EncryptionAlgorithm',
            'EncryptionCertificate',
            'Description',
            'EnableException'
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Backup-DbaDatabase Integration Tests" -Tag 'IntegrationTests' {
    # Shared variables
    $DestBackupDir = 'C:\Temp\backups'
    $random = Get-Random
    $DestDbRandom = "dbatools_ci_backupdbadatabase$random"

    BeforeAll {
        # Ensure the backup directory exists
        if (-not (Test-Path $DestBackupDir)) {
            New-Item -Type Directory -Path $DestBackupDir -Force | Out-Null
        }

        # Clean up databases before tests
        Get-DbaDatabase -SqlInstance $global:instance1 -Database 'dbatoolsci_singlerestore' | Remove-DbaDatabase -Confirm:$false -Force
        Get-DbaDatabase -SqlInstance $global:instance2 -Database $DestDbRandom | Remove-DbaDatabase -Confirm:$false -Force
    }

    AfterAll {
        # Clean up databases after tests
        Get-DbaDatabase -SqlInstance $global:instance1 -Database 'dbatoolsci_singlerestore' | Remove-DbaDatabase -Confirm:$false -Force
        Get-DbaDatabase -SqlInstance $global:instance2 -Database $DestDbRandom | Remove-DbaDatabase -Confirm:$false -Force

        # Clean up backup directory
        if (Test-Path $DestBackupDir) {
            Remove-Item -Path "$DestBackupDir\*" -Force -Recurse
        }
    }

    Context "Properly backs up a database on the local drive using Path" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $DestBackupDir
        }
        It "Should return a database name, specifically master" {
            $results.DatabaseName | Should -Contain 'master'
        }
        It "Should return successful backup" {
            $results.BackupComplete | Should -Be $true
        }
    }

    Context "Should not backup if database and exclude match" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $DestBackupDir -Database 'master' -Exclude 'master'
        }
        It "Should not return any backup objects" {
            $results | Should -BeNullOrEmpty
        }
    }

    Context "No database found to backup should raise warning and null output" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $DestBackupDir -Database 'NonExistentDatabase' -WarningVariable warnvar -WarningAction SilentlyContinue
        }
        It "Should not return any backup objects" {
            $results | Should -BeNullOrEmpty
        }
        It "Should return a warning" {
            $warnvar | Should -Match "No databases match the request for backups"
        }
    }

    Context "Database should backup 1 database" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $DestBackupDir -Database 'master'
            $masterDb = Get-DbaDatabase -SqlInstance $global:instance1 -Database 'master'
        }
        It "Database backup object count Should Be 1" {
            $results.DatabaseName.Count | Should -Be 1
            $results.BackupComplete | Should -Be $true
        }
        It "Database ID should be returned" {
            $results.DatabaseID | Should -Be $masterDb.ID
        }
    }

    Context "Database should backup 2 databases" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $DestBackupDir -Database 'master', 'msdb'
        }
        It "Database backup object count Should Be 2" {
            $results.DatabaseName.Count | Should -Be 2
            $results.BackupComplete | Should -Be @($true, $true)
        }
    }

    Context "Should take path and filename" {
        BeforeAll {
            $backupFileName = 'PesterTest.bak'
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $DestBackupDir -Database 'master' -BackupFileName $backupFileName
            $expectedPath = Join-Path $DestBackupDir $backupFileName
        }
        It "Should report it has backed up to the path with the correct name" {
            $results.FullName | Should -Be $expectedPath
        }
        It "Should have backed up to the path with the correct name" {
            Test-Path $expectedPath | Should -Be $true
        }
    }

    Context "Database parameter works when using pipes (fixes #5044)" {
        BeforeAll {
            $backupFileName = 'PesterTest.bak'
            $results = Get-DbaDatabase -SqlInstance $global:instance1 | Backup-DbaDatabase -Database 'master' -BackupFileName $backupFileName -BackupDirectory $DestBackupDir
            $expectedPath = Join-Path $DestBackupDir $backupFileName
        }
        It "Should report it has backed up to the path with the correct name" {
            $results.FullName | Should -Be $expectedPath
        }
        It "Should have backed up to the path with the correct name" {
            Test-Path $expectedPath | Should -Be $true
        }
    }

    Context "ExcludeDatabase parameter works when using pipes (fixes #5044)" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $global:instance1 | Backup-DbaDatabase -ExcludeDatabase 'master', 'tempdb', 'msdb', 'model'
        }
        It "Should not contain excluded databases" {
            $results.DatabaseName | Should -Not -Contain 'master', 'tempdb', 'msdb', 'model'
        }
    }

    Context "Handling backup paths that don't exist" {
        BeforeAll {
            $MissingPath = Join-Path $DestBackupDir 'Missing1\Awol2'
            $MissingPathTrailing = $MissingPath + '\'
            $resultsWithoutBuildPath = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupDirectory $MissingPath -WarningVariable warnvar -WarningAction SilentlyContinue
            $resultsWithBuildPath = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupDirectory $MissingPathTrailing -BuildPath
        }
        It "Should warn and fail if path doesn't exist and BuildPath not set" {
            $warnvar | Should -Match $MissingPath
            $resultsWithoutBuildPath | Should -BeNullOrEmpty
        }
        It "Should have backed up to $MissingPath when BuildPath is set" {
            $resultsWithBuildPath.BackupFolder | Should -Be $MissingPath
            $resultsWithBuildPath.Path | Should -Not -Match '\\$'
        }
    }

    Context "CreateFolder switch should append the databasename to the backup path" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupDirectory $DestBackupDir -CreateFolder
            $expectedPath = Join-Path $DestBackupDir 'master'
        }
        It "Should have appended master to the backup path" {
            $results.BackupFolder | Should -Be $expectedPath
        }
    }

    Context "CreateFolder switch should append the databasename to the backup path even when striping" {
        BeforeAll {
            $backupPaths = @(
                Join-Path $DestBackupDir 'stripewithdb1',
                Join-Path $DestBackupDir 'stripewithdb2'
            )
            foreach ($path in $backupPaths) {
                if (-not (Test-Path $path)) {
                    New-Item -Type Directory -Path $path -Force | Out-Null
                }
            }
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupDirectory $backupPaths -CreateFolder
            $expectedPaths = $backupPaths | ForEach-Object { Join-Path $_ 'master' }
        }
        It "Should have appended master to all backup paths" {
            $results.BackupFolder | Sort-Object | Should -Be $expectedPaths | Sort-Object
        }
    }

    Context "A fully qualified path should override a backupfolder" {
        BeforeAll {
            $backupFileName = Join-Path $DestBackupDir 'PesterTest2.bak'
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupDirectory 'C:\temp' -BackupFileName $backupFileName
        }
        It "Should report backed up to $DestBackupDir" {
            $results.FullName | Should -Be $backupFileName
            $results.BackupFolder | Should -Not -Be 'C:\temp'
        }
        It "Should have backed up to $backupFileName" {
            Test-Path $backupFileName | Should -Be $true
        }
    }

    Context "Should stripe if multiple backup folders specified" {
        BeforeAll {
            $backupPaths = @(
                Join-Path $DestBackupDir 'stripe1',
                Join-Path $DestBackupDir 'stripe2',
                Join-Path $DestBackupDir 'stripe3'
            )
            foreach ($path in $backupPaths) {
                if (-not (Test-Path $path)) {
                    New-Item -Type Directory -Path $path -Force | Out-Null
                }
            }
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupDirectory $backupPaths
        }
        It "Should have created 3 backups" {
            $results.BackupFilesCount | Should -Be 3
        }
        It "Should have written to all 3 folders" {
            $backupFolders = $results.BackupFolder
            $backupPaths | ForEach-Object {
                $backupFolders | Should -Contain $_
            }
        }
        It "Should have written files with extensions" {
            foreach ($path in $results.BackupFile) {
                [IO.Path]::GetExtension($path) | Should -Be '.bak'
            }
        }
        It "Should have created 3 backups, even when FileCount is different" {
            $resultsWithFileCount = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupDirectory $backupPaths -FileCount 2
            $resultsWithFileCount.BackupFilesCount | Should -Be 3
        }
    }

    Context "Should stripe on FileCount > 1" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupDirectory $DestBackupDir -FileCount 3
        }
        It "Should have created 3 backups" {
            $results.BackupFilesCount | Should -Be 3
        }
    }

    Context "Should build filenames properly" {
        It "Should have one period in file extension" {
            foreach ($path in $results.BackupFile) {
                [IO.Path]::GetExtension($path) | Should -Not -Match '\.\..*'
            }
        }
    }

    Context "Should prefix the filenames when IncrementPrefix set" {
        BeforeAll {
            $fileCount = 3
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupDirectory $DestBackupDir -FileCount $fileCount -IncrementPrefix
        }
        It "Should have created 3 backups" {
            $results.BackupFilesCount | Should -Be 3
        }
        It "Should prefix them correctly" {
            for ($i = 1; $i -le $fileCount; $i++) {
                $results.BackupFile[$i - 1] | Should -Match "^$i-"
            }
        }
    }

    Context "Should backup to default path if none specified" {
        BeforeAll {
            $backupFileName = 'PesterTest.bak'
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupFileName $backupFileName
            $DefaultPath = (Get-DbaDefaultPath -SqlInstance $global:instance1).Backup
            $expectedPath = Join-Path $DefaultPath $backupFileName
        }
        It "Should report it has backed up to the path with the correct name" {
            $results.FullName | Should -Be $expectedPath
        }
        It "Should have backed up to the path with the correct name" {
            Test-Path $expectedPath | Should -Be $true
        }
    }

    Context "Test backup verification" {
        It "Should perform a full backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -Type 'Full' -Verify
            $b.BackupComplete | Should -Be $true
            $b.Verified | Should -Be $true
            $b.Count | Should -Be 1
        }
        It -Skip "Should perform a diff backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'backuptest' -Type 'Diff' -Verify
            $b.BackupComplete | Should -Be $true
            $b.Verified | Should -Be $true
        }
        It -Skip "Should perform a log backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'backuptest' -Type 'Log' -Verify
            $b.BackupComplete | Should -Be $true
            $b.Verified | Should -Be $true
        }
    }

    Context "Backup can pipe to restore" {
        BeforeAll {
            $restorePath = Join-Path $global:appveyorlabrepo 'singlerestore\singlerestore.bak'
            $null = Restore-DbaDatabase -SqlInstance $global:instance1 -Path $restorePath -DatabaseName 'dbatoolsci_singlerestore'
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $DestBackupDir -Database 'dbatoolsci_singlerestore' |
                Restore-DbaDatabase -SqlInstance $global:instance2 -DatabaseName $DestDbRandom -TrustDbBackupHistory -ReplaceDbNameInFile
        }
        It "Should return successful restore" {
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Test Backup-DbaDatabase can take pipe input" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $global:instance1 -Database 'master' | Backup-DbaDatabase -Confirm:$false -WarningVariable warnvar -WarningAction SilentlyContinue
        }
        It "Should not warn" {
            $warnvar | Should -BeNullOrEmpty
        }
        It "Should complete successfully" {
            $results.BackupComplete | Should -Be $true
        }
    }

    Context "Should handle NUL as an input path" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupFileName 'NUL'
        }
        It "Should return successful backup" {
            $results.BackupComplete | Should -Be $true
        }
        It "Should have backed up to NUL:" {
            $results.FullName[0] | Should -Be 'NUL:'
        }
    }

    Context "Should only output a T-SQL String if OutputScriptOnly specified" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupFileName 'c:\notexists\file.bak' -OutputScriptOnly
        }
        It "Should return a string" {
            $results.GetType().ToString() | Should -Be 'System.String'
        }
        It "Should return the correct T-SQL backup script" {
            $results | Should -Be "BACKUP DATABASE [master] TO  DISK = N'c:\notexists\file.bak' WITH NOFORMAT, NOINIT, NOSKIP, REWIND, NOUNLOAD,  STATS = 1"
        }
    }

    Context "Should handle an encrypted database when compression is specified" {
        BeforeAll {
            $sqlencrypt = @"
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<UseStrongPasswordHere>';
GO
CREATE CERTIFICATE MyServerCert WITH SUBJECT = 'My DEK Certificate';
GO
CREATE DATABASE encrypted;
GO
"@
            $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query $sqlencrypt -Database 'master'
            $createdb = @"
USE [encrypted];
GO
CREATE DATABASE ENCRYPTION KEY
WITH ALGORITHM = AES_128
ENCRYPTION BY SERVER CERTIFICATE MyServerCert;
GO
ALTER DATABASE encrypted
SET ENCRYPTION ON;
GO
"@
            $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query $createdb -Database 'encrypted'
            $results = Backup-DbaDatabase -SqlInstance $global:instance2 -Database 'encrypted' -Compress
        }
        It "Should compress an encrypted database" {
            $results.Script | Should -Match 'COMPRESSION'
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance2 -Database 'encrypted' -Confirm:$false
            $sqldrop = @"
DROP CERTIFICATE MyServerCert;
GO
DROP MASTER KEY;
GO
"@
            $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query $sqldrop -Database 'master'
        }
    }

    Context "Custom TimeStamp" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master' -BackupDirectory $DestBackupDir -TimeStampFormat 'bobob'
        }
        It "Should apply the correct custom Timestamp" {
            ($results | Where-Object { $_.BackupPath -like '*bobob*' }).Count | Should -Be $results.Count
        }
    }

    Context "Test Backup templating" {
        BeforeAll {
            $backupDirectory = Join-Path $DestBackupDir 'dbname\instancename\backuptype\'
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database 'master', 'msdb' -BackupDirectory $backupDirectory -BackupFileName 'dbname-backuptype.bak' -ReplaceInName -BuildPath
            $instanceName = ($global:instance1).Split('\')[1]
            $expectedPaths = @(
                Join-Path $DestBackupDir "master\$instanceName\Full\master-Full.bak",
                Join-Path $DestBackupDir "msdb\$instanceName\Full\msdb-Full.bak"
            )
        }
        It "Should have replaced the markers" {
            $results[0].BackupPath | Should -Be $expectedPaths[0]
            $results[1].BackupPath | Should -Be $expectedPaths[1]
        }
    }

    Context "Test Backup templating when db object piped in issue 8100" {
        BeforeAll {
            $backupDirectory = Join-Path $DestBackupDir 'db2\dbname\instancename\backuptype\'
            $results = Get-DbaDatabase -SqlInstance $global:instance1 -Database 'master', 'msdb' | Backup-DbaDatabase -BackupDirectory $backupDirectory -BackupFileName 'dbname-backuptype.bak' -ReplaceInName -BuildPath
            $instanceName = ($global:instance1).Split('\')[1]
            $expectedPaths = @(
                Join-Path $DestBackupDir "db2\master\$instanceName\Full\master-Full.bak",
                Join-Path $DestBackupDir "db2\msdb\$instanceName\Full\msdb-Full.bak"
            )
        }
        It "Should have replaced the markers" {
            $results[0].BackupPath | Should -Be $expectedPaths[0]
            $results[1].BackupPath | Should -Be $expectedPaths[1]
        }
    }

    Context "Test Backup Encryption with Certificate" {
        BeforeAll {
            $securePass = ConvertTo-SecureString "TestPassword1" -AsPlainText -Force
            New-DbaDbMasterKey -SqlInstance $global:instance2 -Database 'master' -SecurePassword $securePass -Confirm:$false -ErrorAction SilentlyContinue
            $cert = New-DbaDbCertificate -SqlInstance $global:instance2 -Database 'master' -Name 'BackupCertt' -Subject 'BackupCertt'
            $encBackupResults = Backup-DbaDatabase -SqlInstance $global:instance2 -Database 'master' -EncryptionAlgorithm 'AES128' -EncryptionCertificate 'BackupCertt' -BackupFileName 'encryptiontest.bak' -Description "Encrypted backup"
        }
        It "Should encrypt the backup" {
            $encBackupResults.EncryptorType | Should -Be "CERTIFICATE"
            $encBackupResults.KeyAlgorithm | Should -Be "aes_128"
            Test-Path $encBackupResults.FullName | Should -Be $true
        }
        AfterAll {
            Remove-DbaDbCertificate -SqlInstance $global:instance2 -Database 'master' -Certificate 'BackupCertt' -Confirm:$false
            Remove-DbaDbMasterKey -SqlInstance $global:instance2 -Database 'master' -Confirm:$false
            Remove-Item -Path $encBackupResults.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Azure works" -Skip:([string]::IsNullOrEmpty($env:azurepasswd)) {
        BeforeAll {
            # Azure setup code
            Get-DbaDatabase -SqlInstance $global:instance2 -Database 'dbatoolsci_azure' | Remove-DbaDatabase -Confirm:$false -Force
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            if (Get-DbaCredential -SqlInstance $global:instance2 -Name "[$global:azureblob]" ) {
                $server.Query("DROP CREDENTIAL [$global:azureblob]")
            }
            $server.Query("CREATE CREDENTIAL [$global:azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'")
            $server.Query("CREATE DATABASE dbatoolsci_azure")
            if (Get-DbaCredential -SqlInstance $global:instance2 -Name 'dbatools_ci') {
                $server.Query("DROP CREDENTIAL [dbatools_ci]")
            }
            $server.Query("CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$global:azureblobaccount', SECRET = N'$env:azurelegacypasswd'")
        }
        AfterAll {
            # Azure cleanup code
            Get-DbaDatabase -SqlInstance $global:instance2 -Database 'dbatoolsci_azure' | Remove-DbaDatabase -Confirm:$false -Force
            $server.Query("DROP CREDENTIAL [$global:azureblob]")
            $server.Query("DROP CREDENTIAL [dbatools_ci]")
        }
        It "Backs up to Azure properly using SHARED ACCESS SIGNATURE" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance2 -AzureBaseUrl $global:azureblob -Database 'dbatoolsci_azure' -BackupFileName 'dbatoolsci_azure.bak' -WithFormat
            $results.Database | Should -Be 'dbatoolsci_azure'
            $results.DeviceType | Should -Be 'URL'
            $results.BackupFile | Should -Be 'dbatoolsci_azure.bak'
        }
        It "Backs up to Azure properly using legacy credential" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance2 -AzureBaseUrl $global:azureblob -Database 'dbatoolsci_azure' -BackupFileName 'dbatoolsci_azure2.bak' -WithFormat -AzureCredential 'dbatools_ci'
            $results.Database | Should -Be 'dbatoolsci_azure'
            $results.DeviceType | Should -Be 'URL'
            $results.BackupFile | Should -Be 'dbatoolsci_azure2.bak'
        }
    }
}

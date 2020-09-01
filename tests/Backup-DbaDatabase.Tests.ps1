$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Path', 'FilePath', 'ReplaceInName', 'CopyOnly', 'Type', 'InputObject', 'CreateFolder', 'FileCount', 'CompressBackup', 'Checksum', 'Verify', 'MaxTransferSize', 'BlockSize', 'BufferCount', 'AzureBaseUrl', 'AzureCredential', 'NoRecovery', 'BuildPath', 'WithFormat', 'Initialize', 'SkipTapeHeader', 'TimeStampFormat', 'IgnoreFileChecks', 'OutputScriptOnly', 'EnableException', 'EncryptionAlgorithm', 'EncryptionCertificate', 'IncrementPrefix'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Properly restores a database on the local drive using Path" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory C:\temp\backups
        It "Should return a database name, specifically master" {
            ($results.DatabaseName -contains 'master') | Should -Be $true
        }
        It "Should return successful restore" {
            $results.ForEach{ $_.BackupComplete | Should -Be $true }
        }
    }

    BeforeAll {
        $DestBackupDir = 'C:\Temp\backups'
        $random = Get-Random
        $DestDbRandom = "dbatools_ci_backupdbadatabase$random"
        if (-Not(Test-Path $DestBackupDir)) {
            New-Item -Type Container -Path $DestBackupDir
        }
        Get-DbaDatabase -SqlInstance $script:instance1 -Database "dbatoolsci_singlerestore" | Remove-DbaDatabase -Confirm:$false
        Get-DbaDatabase -SqlInstance $script:instance2 -Database $DestDbRandom | Remove-DbaDatabase -Confirm:$false
    }
    AfterAll {
        Get-DbaDatabase -SqlInstance $script:instance1 -Database "dbatoolsci_singlerestore" | Remove-DbaDatabase -Confirm:$false
        Get-DbaDatabase -SqlInstance $script:instance2 -Database $DestDbRandom | Remove-DbaDatabase -Confirm:$false
        if (Test-Path $DestBackupDir) {
            Remove-Item "$DestBackupDir\*" -Force -Recurse
        }
    }
    Context "Should not backup if database and exclude match" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory $DestBackupDir -Database master -Exclude master
        It "Should not return object" {
            $results | Should -Be $null
        }
    }

    Context "No database found to backup should raise warning and null output" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory $DestBackupDir -Database AliceDoesntDBHereAnyMore -WarningVariable warnvar
        It "Should not return object" {
            $results | Should -Be $null
        }
        It "Should return a warning" {
            $warnvar | Should -BeLike "*No databases match the request for backups*"
        }
    }

    Context "Database should backup 1 database" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory $DestBackupDir -Database master
        It "Database backup object count Should Be 1" {
            $results.DatabaseName.Count | Should -Be 1
            $results.BackupComplete | Should -Be $true
        }
    }

    Context "Database should backup 2 databases" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory $DestBackupDir -Database master, msdb
        It "Database backup object count Should Be 2" {
            $results.DatabaseName.Count | Should -Be 2
            $results.BackupComplete | Should -Be @($true, $true)
        }
    }

    Context "Should take path and filename" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory $DestBackupDir -Database master -BackupFileName 'PesterTest.bak'
        It "Should report it has backed up to the path with the correct name" {
            $results.Fullname | Should -BeLike "$DestBackupDir*PesterTest.bak"
        }
        It "Should have backed up to the path with the correct name" {
            Test-Path "$DestBackupDir\PesterTest.bak" | Should -Be $true
        }
    }

    Context "Database parameter works when using pipes (fixes #5044)" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 | Backup-DbaDatabase -Database master -BackupFileName PesterTest.bak -BackupDirectory $DestBackupDir
        It "Should report it has backed up to the path with the correct name" {
            $results.Fullname | Should -BeLike "$DestBackupDir*PesterTest.bak"
        }
        It "Should have backed up to the path with the correct name" {
            Test-Path "$DestBackupDir\PesterTest.bak" | Should -Be $true
        }
    }

    Context "ExcludeDatabase parameter works when using pipes (fixes #5044)" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 | Backup-DbaDatabase -ExcludeDatabase master, tempdb, msdb, model
        It "Should report it has backed up to the path with the correct name" {
            $results.DatabaseName | Should -Not -Contain master
            $results.DatabaseName | Should -Not -Contain tempdb
            $results.DatabaseName | Should -Not -Contain msdb
            $results.DatabaseName | Should -Not -Contain model
        }
    }

    Context "Handling backup paths that don't exist" {
        $MissingPathTrailing = "$DestBackupDir\Missing1\Awol2\"
        $MissingPath = "$DestBackupDir\Missing1\Awol2"
        $null = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory $MissingPath -WarningVariable warnvar *>$null
        It "Should warn and fail if path doesn't exist and BuildPath not set" {
            $warnvar | Should -BeLike "*$MissingPath*"
        }
        # $MissingPathTrailing has a trailing slash but we normalize the path before doing the actual backup
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory $MissingPathTrailing -WarningVariable warnvar -BuildPath
        It "Should have backed up to $MissingPath" {
            $results.BackupFolder | Should -Be "$MissingPath"

            $results.Path | Should -Not -BeLike '*\\*'
        }
    }

    Context "CreateFolder switch should append the databasename to the backup path" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory $DestBackupDir -CreateFolder
        It "Should have appended master to the backup path" {
            $results.BackupFolder | Should -Be "$DestBackupDir\master"
        }
    }

    Context "CreateFolder switch should append the databasename to the backup path even when striping" {
        $backupPaths = "$DestBackupDir\stripewithdb1", "$DestBackupDir\stripewithdb2"
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory $backupPaths -CreateFolder
        It "Should have appended master to all backup paths" {
            foreach ($path in $results.BackupFolder) {
                ($results.BackupFolder | Sort-Object) | Should -Be ($backupPaths | Sort-Object | ForEach-Object { [IO.Path]::Combine($_, 'master') })
            }
        }
    }


    Context "A fully qualified path should override a backupfolder" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory c:\temp -BackupFileName "$DestBackupDir\PesterTest2.bak"
        It "Should report backed up to $DestBackupDir" {
            $results.FullName | Should -BeLike "$DestBackupDir\PesterTest2.bak"
            $results.BackupFolder | Should Not Be 'c:\temp'
        }
        It "Should have backuped up to $DestBackupDir\PesterTest2.bak" {
            Test-Path "$DestBackupDir\PesterTest2.bak" | Should -Be $true
        }
    }

    Context "Should stripe if multiple backupfolders specified" {
        $backupPaths = "$DestBackupDir\stripe1", "$DestBackupDir\stripe2", "$DestBackupDir\stripe3"
        $null = New-item -Path $backupPaths -ItemType Directory


        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory $backupPaths
        It "Should have created 3 backups" {
            $results.BackupFilesCount | Should -Be 3
        }
        It "Should have written to all 3 folders" {
            $backupPaths | ForEach-Object {
                $_ | Should -BeIn ($results.BackupFolder)
            }
        }
        It "Should have written files with extensions" {
            foreach ($path in $results.BackupFile) {
                [IO.Path]::GetExtension($path) | Should -Be '.bak'
            }
        }
        # Assure that striping logic favours -BackupDirectory and not -Filecount
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory $backupPaths -FileCount 2
        It "Should have created 3 backups, even when FileCount is different" {
            $results.BackupFilesCount | Should -Be 3
        }
    }

    Context "Should stripe on filecount > 1" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory $DestBackupDir -FileCount 3
        It "Should have created 3 backups" {
            $results.BackupFilesCount | Should -Be 3
        }
    }

    Context "Should build filenames properly" {
        It "Should have 1 period in file extension" {
            foreach ($path in $results.BackupFile) {
                [IO.Path]::GetExtension($path) | Should -Not -BeLike '*..*'
            }
        }
    }

    Context "Should prefix the filenames when IncrementPrefix set" {
        $fileCount = 3
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory $DestBackupDir -FileCount $fileCount -IncrementPrefix
        It "Should have created 3 backups" {
            $results.BackupFilesCount | Should -Be 3
        }
        It "Should prefix them correctly" {
            for ($i = 1; $i -le $fileCount; $i++) {
                $results.BackupFile[$i - 1] | Should -BeLike "$i-*"
            }
        }
    }

    Context "Should Backup to default path if none specified" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupFileName 'PesterTest.bak'
        $DefaultPath = (Get-DbaDefaultPath -SqlInstance $script:instance1).Backup
        It "Should report it has backed up to the path with the corrrect name" {
            $results.Fullname | Should -BeLike "$DefaultPath*PesterTest.bak"
        }
        It "Should have backed up to the path with the corrrect name" {
            Test-Path "$DefaultPath\PesterTest.bak" | Should -Be $true
        }
    }

    Context "Test backup  verification" {
        It "Should perform a full backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -Type full -Verify
            $b.BackupComplete | Should -Be $True
            $b.Verified | Should -Be $True
            $b.count | Should -Be 1
        }
        It -Skip "Should perform a diff backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $script:instance1 -Database backuptest -Type diff -Verify
            $b.BackupComplete | Should -Be $True
            $b.Verified | Should -Be $True
        }
        It -Skip "Should perform a log backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $script:instance1 -Database backuptest -Type log -Verify
            $b.BackupComplete | Should -Be $True
            $b.Verified | Should -Be $True
        }
    }

    Context "Backup can pipe to restore" {
        $null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName "dbatoolsci_singlerestore"
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -BackupDirectory $DestBackupDir -Database "dbatoolsci_singlerestore" | Restore-DbaDatabase -SqlInstance $script:instance2 -DatabaseName $DestDbRandom -TrustDbBackupHistory -ReplaceDbNameInFile
        It "Should return successful restore" {
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Test Backup-DbaDatabase can take pipe input" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -Database master | Backup-DbaDatabase -confirm:$false -WarningVariable warnvar
        It "Should not warn" {
            '' -eq $warnvar | Should -Be $True
        }
        It "Should Complete Successfully" {
            $results.BackupComplete | Should -Be $true
        }

    }

    Context "Should handle NUL as an input path" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupFileName NUL
        It "Should return succesful backup" {
            $results.BackupComplete | Should -Be $true
        }
        It "Should have backed up to NUL:" {
            $results.FullName[0] | Should -Be 'NUL:'
        }
    }

    Context "Should only output a T-SQL String if OutputScriptOnly specified" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupFileName c:\notexists\file.bak -OutputScriptOnly
        It "Should return a string" {
            $results.GetType().ToString() | Should -Be 'System.String'
        }
        It "Should return BACKUP DATABASE [master] TO  DISK = N'c:\notexists\file.bak' WITH NOFORMAT, NOINIT, NOSKIP, REWIND, NOUNLOAD,  STATS = 1" {
            $results | Should -Be "BACKUP DATABASE [master] TO  DISK = N'c:\notexists\file.bak' WITH NOFORMAT, NOINIT, NOSKIP, REWIND, NOUNLOAD,  STATS = 1"
        }
    }

    Context "Should handle an encrypted database when compression is specified" {
        $sqlencrypt =
        @"
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<UseStrongPasswordHere>';
go
CREATE CERTIFICATE MyServerCert WITH SUBJECT = 'My DEK Certificate';
go
CREATE DATABASE encrypted
go
"@
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query $sqlencrypt -Database Master
        $createdb =
        @"
CREATE DATABASE ENCRYPTION KEY
WITH ALGORITHM = AES_128
ENCRYPTION BY SERVER CERTIFICATE MyServerCert;
GO
ALTER DATABASE encrypted
SET ENCRYPTION ON;
GO
"@
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query $createdb -Database encrypted
        It "Should not compress an encrypted db" {
            $results = Backup-DbaDatabase -SqlInstance $script:instance2 -Database encrypted -Compress
            $results.script | Should -BeLike '*NO_COMPRESSION*'
        }
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database encrypted -confirm:$false
        $sqldrop =
        @"
drop certificate MyServerCert
go
drop master key
go
"@
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query $sqldrop -Database Master
    }

    Context "Custom TimeStamp" {
        # Test relies on DateFormat bobob returning bobob as the values aren't interpreted, check here in case .Net rules change
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory $DestBackupDir -TimeStampFormat bobob
        It "Should apply the corect custom Timestamp" {
            ($results | Where-Object { $_.BackupPath -like '*bobob*' }).count | Should -Be $results.count
        }
    }

    Context "Test Backup templating" {
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database master -BackupDirectory $DestBackupDir\dbname\instancename\backuptype\  -BackupFileName dbname-backuptype.bak -ReplaceInName -BuildPath
        It "Should have replaced the markers" {
            $results.BackupPath | Should -BeLike "$DestBackupDir\master\$(($script:instance1).split('\')[1])\Full\master-Full.bak"
        }
    }

    Context "Test Backup Encryption with Certificate" {
        $securePass = ConvertTo-SecureString "estBackupDir\master\script:instance1).split('\')[1])\Full\master-Full.bak" -AsPlainText -Force
        New-DbaDbMasterKey -SqlInstance $script:instance2 -Database Master -SecurePassword $securePass -confirm:$false
        $cert = New-DbaDbCertificate -SqlInstance $script:instance2 -Database master -Name BackupCertt -Subject BackupCertt
        $encBackupResults = Backup-DbaDatabase -SqlInstance $script:instance2 -Database master -EncryptionAlgorithm AES128 -EncryptionCertificate BackupCertt -BackupFileName 'encryptiontest.bak'
        It "Should encrypt the backup" {
            $encBackupResults.EncryptorType | Should Be "CERTIFICATE"
            $encBackupResults.KeyAlgorithm | Should Be "aes_128"
        }
        Remove-DbaDbCertificate -SqlInstance $script:instance2 -Database master -Certificate BackupCertt -Confirm:$false
        Remove-DbaDbMasterKey -SqlInstance $script:instance2 -Database Master -confirm:$false
    }

    # Context "Test Backup Encryption with Asymmetric Key" {
    #     $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Database master -Name BackupKey
    #     $encBackupResults = Backup-DbaDatabase -SqlInstance $script:instance2 -Database master -EncryptionAlgorithm AES128 -EncryptionKey BackupKey
    #     It "Should encrypt the backup" {
    #         $encBackupResults.EncryptorType | Should Be "CERTIFICATE"
    #         $encBackupResults.KeyAlgorithm | Should Be "aes_128"
    #     }
    #     remove-DbaDbCertificate -SqlInstance $script:instance2 -Database master -Certificate BackupCertt -Confirm:$false
    # }

    if ($env:azurepasswd) {
        Context "Azure works" {
            BeforeAll {
                Get-DbaDatabase -SqlInstance $script:instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase -Confirm:$false
                $server = Connect-DbaInstance -SqlInstance $script:instance2
                if (Get-DbaCredential -SqlInstance $script:instance2 -Name "[$script:azureblob]" ) {
                    $sql = "DROP CREDENTIAL [$script:azureblob]"
                    $server.Query($sql)
                }
                $sql = "CREATE CREDENTIAL [$script:azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
                $server.Query($sql)
                $server.Query("CREATE DATABASE dbatoolsci_azure")
                if (Get-DbaCredential -SqlInstance $script:instance2 -name dbatools_ci) {
                    $sql = "DROP CREDENTIAL dbatools_ci"
                    $server.Query($sql)
                }
                $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$script:azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
                $server.Query($sql)
            }
            AfterAll {
                Get-DbaDatabase -SqlInstance $script:instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase -Confirm:$false
                $server.Query("DROP CREDENTIAL [$script:azureblob]")
            }
            It "backs up to Azure properly using SHARED ACCESS SIGNATURE" {
                $results = Backup-DbaDatabase -SqlInstance $script:instance2 -AzureBaseUrl $script:azureblob -Database dbatoolsci_azure -BackupFileName dbatoolsci_azure.bak -WithFormat
                $results.Database | Should -Be 'dbatoolsci_azure'
                $results.DeviceType | Should -Be 'URL'
                $results.BackupFile | Should -Be 'dbatoolsci_azure.bak'
            }
            It "backs up to Azure properly using legacy credential" {
                $results = Backup-DbaDatabase -SqlInstance $script:instance2 -AzureBaseUrl $script:azureblob -Database dbatoolsci_azure -BackupFileName dbatoolsci_azure2.bak -WithFormat -AzureCredential dbatools_ci
                $results.Database | Should -Be 'dbatoolsci_azure'
                $results.DeviceType | Should -Be 'URL'
                $results.BackupFile | Should -Be 'dbatoolsci_azure2.bak'
            }
        }
    }
}

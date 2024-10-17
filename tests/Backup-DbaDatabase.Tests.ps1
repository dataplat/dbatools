param($ModuleName = 'dbatools')

Describe "Backup-DbaDatabase Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Import module and set up any necessary test data
        Import-Module $ModuleName
    }

    Context "Validate parameters" {
        BeforeAll {
            $commandName = "Backup-DbaDatabase"
            $command = Get-Command -Name $commandName -Module $ModuleName
        }

        It "Should have SqlInstance parameter" {
            $command | Should -HaveParameter SqlInstance -Type DbaInstanceParameter -Mandatory:$false
        }

        It "Should have SqlCredential parameter" {
            $command | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }

        It "Should have Database parameter" {
            $command | Should -HaveParameter Database -Type Object[] -Mandatory:$false
        }

        It "Should have ExcludeDatabase parameter" {
            $command | Should -HaveParameter ExcludeDatabase -Type Object[] -Mandatory:$false
        }

        It "Should have Path parameter" {
            $command | Should -HaveParameter Path -Type String[] -Mandatory:$false
        }

        It "Should have FilePath parameter" {
            $command | Should -HaveParameter FilePath -Type String -Mandatory:$false
        }

        It "Should have IncrementPrefix parameter" {
            $command | Should -HaveParameter IncrementPrefix -Type Switch
        }

        It "Should have ReplaceInName parameter" {
            $command | Should -HaveParameter ReplaceInName -Type Switch
        }

        It "Should have NoAppendDbNameInPath parameter" {
            $command | Should -HaveParameter NoAppendDbNameInPath -Type Switch
        }

        It "Should have CopyOnly parameter" {
            $command | Should -HaveParameter CopyOnly -Type Switch
        }

        It "Should have Type parameter" {
            $command | Should -HaveParameter Type -Type String -Mandatory:$false
        }

        It "Should have InputObject parameter" {
            $command | Should -HaveParameter InputObject -Type Object[] -Mandatory:$false
        }

        It "Should have CreateFolder parameter" {
            $command | Should -HaveParameter CreateFolder -Type Switch
        }

        It "Should have FileCount parameter" {
            $command | Should -HaveParameter FileCount -Type Int32 -Mandatory:$false
        }

        It "Should have CompressBackup parameter" {
            $command | Should -HaveParameter CompressBackup -Type Switch
        }

        It "Should have Checksum parameter" {
            $command | Should -HaveParameter Checksum -Type Switch
        }

        It "Should have Verify parameter" {
            $command | Should -HaveParameter Verify -Type Switch
        }

        It "Should have MaxTransferSize parameter" {
            $command | Should -HaveParameter MaxTransferSize -Type Int32 -Mandatory:$false
        }

        It "Should have BlockSize parameter" {
            $command | Should -HaveParameter BlockSize -Type Int32 -Mandatory:$false
        }

        It "Should have BufferCount parameter" {
            $command | Should -HaveParameter BufferCount -Type Int32 -Mandatory:$false
        }

        It "Should have AzureBaseUrl parameter" {
            $command | Should -HaveParameter AzureBaseUrl -Type String[] -Mandatory:$false
        }

        It "Should have AzureCredential parameter" {
            $command | Should -HaveParameter AzureCredential -Type String -Mandatory:$false
        }

        It "Should have NoRecovery parameter" {
            $command | Should -HaveParameter NoRecovery -Type Switch
        }

        It "Should have BuildPath parameter" {
            $command | Should -HaveParameter BuildPath -Type Switch
        }

        It "Should have WithFormat parameter" {
            $command | Should -HaveParameter WithFormat -Type Switch
        }

        It "Should have Initialize parameter" {
            $command | Should -HaveParameter Initialize -Type Switch
        }

        It "Should have SkipTapeHeader parameter" {
            $command | Should -HaveParameter SkipTapeHeader -Type Switch
        }

        It "Should have TimeStampFormat parameter" {
            $command | Should -HaveParameter TimeStampFormat -Type String -Mandatory:$false
        }

        It "Should have IgnoreFileChecks parameter" {
            $command | Should -HaveParameter IgnoreFileChecks -Type Switch
        }

        It "Should have OutputScriptOnly parameter" {
            $command | Should -HaveParameter OutputScriptOnly -Type Switch
        }

        It "Should have EncryptionAlgorithm parameter" {
            $command | Should -HaveParameter EncryptionAlgorithm -Type String -Mandatory:$false
        }

        It "Should have EncryptionCertificate parameter" {
            $command | Should -HaveParameter EncryptionCertificate -Type String -Mandatory:$false
        }

        It "Should have Description parameter" {
            $command | Should -HaveParameter Description -Type String -Mandatory:$false
        }

        It "Should have EnableException parameter" {
            $command | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Backup-DbaDatabase Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $global:instance1 = "localhost"
        $global:instance2 = "localhost\SQL2019"
        $global:appveyorlabrepo = "C:\github\appveyor-lab"
        $global:DestBackupDir = 'C:\Temp\backups'
        $global:random = Get-Random
        $global:DestDbRandom = "dbatools_ci_backupdbadatabase$global:random"

        # Create backup directory if it doesn't exist
        if (-not (Test-Path $global:DestBackupDir)) {
            New-Item -Type Container -Path $global:DestBackupDir
        }

        # Remove test databases if they exist
        Get-DbaDatabase -SqlInstance $global:instance1 -Database "dbatoolsci_singlerestore" | Remove-DbaDatabase -Confirm:$false
        Get-DbaDatabase -SqlInstance $global:instance2 -Database $global:DestDbRandom | Remove-DbaDatabase -Confirm:$false
    }

    AfterAll {
        # Clean up test databases and backup files
        Get-DbaDatabase -SqlInstance $global:instance1 -Database "dbatoolsci_singlerestore" | Remove-DbaDatabase -Confirm:$false
        Get-DbaDatabase -SqlInstance $global:instance2 -Database $global:DestDbRandom | Remove-DbaDatabase -Confirm:$false
        if (Test-Path $global:DestBackupDir) {
            Remove-Item "$global:DestBackupDir\*" -Force -Recurse
        }
    }

    Context "Properly restores a database on the local drive using Path" {
        It "Should return a database name, specifically master" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $global:DestBackupDir
            $results.DatabaseName | Should -Contain 'master'
        }

        It "Should return successful restore" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $global:DestBackupDir
            $results | ForEach-Object { $_.BackupComplete | Should -Be $true }
        }
    }

    Context "Should not backup if database and exclude match" {
        It "Should not return object" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $global:DestBackupDir -Database master -Exclude master
            $results | Should -BeNullOrEmpty
        }
    }

    Context "No database found to backup should raise warning and null output" {
        It "Should not return object and should return a warning" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $global:DestBackupDir -Database AliceDoesntDBHereAnyMore -WarningVariable warnvar -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            $warnvar | Should -BeLike "*No databases match the request for backups*"
        }
    }

    Context "Database should backup 1 database" {
        It "Database backup object count Should Be 1" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $global:DestBackupDir -Database master
            $results.DatabaseName.Count | Should -Be 1
            $results.BackupComplete | Should -Be $true
        }

        It "Database ID should be returned" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $global:DestBackupDir -Database master
            $masterDb = Get-DbaDatabase -SqlInstance $global:instance1 -Database master
            $results.DatabaseID | Should -Be $masterDb.ID
        }
    }

    Context "Database should backup 2 databases" {
        It "Database backup object count Should Be 2" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $global:DestBackupDir -Database master, msdb
            $results.DatabaseName.Count | Should -Be 2
            $results.BackupComplete | Should -Be @($true, $true)
        }
    }

    Context "Should take path and filename" {
        It "Should report it has backed up to the path with the correct name" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $global:DestBackupDir -Database master -BackupFileName 'PesterTest.bak'
            $results.Fullname | Should -BeLike "$global:DestBackupDir*PesterTest.bak"
        }

        It "Should have backed up to the path with the correct name" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $global:DestBackupDir -Database master -BackupFileName 'PesterTest.bak'
            Test-Path "$global:DestBackupDir\PesterTest.bak" | Should -Be $true
        }
    }

    Context "Database parameter works when using pipes (fixes #5044)" {
        It "Should report it has backed up to the path with the correct name" {
            $results = Get-DbaDatabase -SqlInstance $global:instance1 | Backup-DbaDatabase -Database master -BackupFileName PesterTest.bak -BackupDirectory $global:DestBackupDir
            $results.Fullname | Should -BeLike "$global:DestBackupDir*PesterTest.bak"
        }

        It "Should have backed up to the path with the correct name" {
            $results = Get-DbaDatabase -SqlInstance $global:instance1 | Backup-DbaDatabase -Database master -BackupFileName PesterTest.bak -BackupDirectory $global:DestBackupDir
            Test-Path "$global:DestBackupDir\PesterTest.bak" | Should -Be $true
        }
    }

    Context "ExcludeDatabase parameter works when using pipes (fixes #5044)" {
        It "Should not contain excluded databases" {
            $results = Get-DbaDatabase -SqlInstance $global:instance1 | Backup-DbaDatabase -ExcludeDatabase master, tempdb, msdb, model
            $results.DatabaseName | Should -Not -Contain master
            $results.DatabaseName | Should -Not -Contain tempdb
            $results.DatabaseName | Should -Not -Contain msdb
            $results.DatabaseName | Should -Not -Contain model
        }
    }



    Context "Handling backup paths that don't exist" {
        $MissingPathTrailing = "$DestBackupDir\Missing1\Awol2\"
        $MissingPath = "$DestBackupDir\Missing1\Awol2"
        $null = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupDirectory $MissingPath -WarningVariable warnvar *>$null
        It "Should warn and fail if path doesn't exist and BuildPath not set" {
            $warnvar | Should -BeLike "*$MissingPath*"
        }
        # $MissingPathTrailing has a trailing slash but we normalize the path before doing the actual backup
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupDirectory $MissingPathTrailing -BuildPath
        It "Should have backed up to $MissingPath" {
            $results.BackupFolder | Should -Be "$MissingPath"
            $results.Path | Should -Not -BeLike '*\\*'
        }
    }

    Context "CreateFolder switch should append the databasename to the backup path" {
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupDirectory $DestBackupDir -CreateFolder
        It "Should have appended master to the backup path" {
            $results.BackupFolder | Should -Be "$DestBackupDir\master"
        }
    }

    Context "CreateFolder switch should append the databasename to the backup path even when striping" {
        $backupPaths = "$DestBackupDir\stripewithdb1", "$DestBackupDir\stripewithdb2"
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupDirectory $backupPaths -CreateFolder
        It "Should have appended master to all backup paths" {
            foreach ($path in $results.BackupFolder) {
                ($results.BackupFolder | Sort-Object) | Should -Be ($backupPaths | Sort-Object | ForEach-Object { [IO.Path]::Combine($_, 'master') })
            }
        }
    }


    Context "A fully qualified path should override a backupfolder" {
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupDirectory c:\temp -BackupFileName "$DestBackupDir\PesterTest2.bak"
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
        $null = New-Item -Path $backupPaths -ItemType Directory


        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupDirectory $backupPaths
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
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupDirectory $backupPaths -FileCount 2
        It "Should have created 3 backups, even when FileCount is different" {
            $results.BackupFilesCount | Should -Be 3
        }
    }

    Context "Should stripe on filecount > 1" {
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupDirectory $DestBackupDir -FileCount 3
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
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupDirectory $DestBackupDir -FileCount $fileCount -IncrementPrefix
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
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupFileName 'PesterTest.bak'
        $DefaultPath = (Get-DbaDefaultPath -SqlInstance $global:instance1).Backup
        It "Should report it has backed up to the path with the corrrect name" {
            $results.Fullname | Should -BeLike "$DefaultPath*PesterTest.bak"
        }
        It "Should have backed up to the path with the corrrect name" {
            Test-Path "$DefaultPath\PesterTest.bak" | Should -Be $true
        }
    }

    Context "Test backup  verification" {
        It "Should perform a full backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -Type full -Verify
            $b.BackupComplete | Should -Be $True
            $b.Verified | Should -Be $True
            $b.count | Should -Be 1
        }
        It -Skip "Should perform a diff backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $global:instance1 -Database backuptest -Type diff -Verify
            $b.BackupComplete | Should -Be $True
            $b.Verified | Should -Be $True
        }
        It -Skip "Should perform a log backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $global:instance1 -Database backuptest -Type log -Verify
            $b.BackupComplete | Should -Be $True
            $b.Verified | Should -Be $True
        }
    }

    Context "Backup can pipe to restore" {
        $null = Restore-DbaDatabase -SqlInstance $global:instance1 -Path $global:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName "dbatoolsci_singlerestore"
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -BackupDirectory $DestBackupDir -Database "dbatoolsci_singlerestore" | Restore-DbaDatabase -SqlInstance $global:instance2 -DatabaseName $DestDbRandom -TrustDbBackupHistory -ReplaceDbNameInFile
        It "Should return successful restore" {
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Test Backup-DbaDatabase can take pipe input" {
        $results = Get-DbaDatabase -SqlInstance $global:instance1 -Database master | Backup-DbaDatabase -confirm:$false -WarningVariable warnvar 3> $null
        It "Should not warn" {
            $warnvar | Should -BeNullOrEmpty
        }
        It "Should Complete Successfully" {
            $results.BackupComplete | Should -Be $true
        }

    }

    Context "Should handle NUL as an input path" {
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupFileName NUL
        It "Should return succesful backup" {
            $results.BackupComplete | Should -Be $true
        }
        It "Should have backed up to NUL:" {
            $results.FullName[0] | Should -Be 'NUL:'
        }
    }

    Context "Should only output a T-SQL String if OutputScriptOnly specified" {
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupFileName c:\notexists\file.bak -OutputScriptOnly
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
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query $sqlencrypt -Database Master
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
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query $createdb -Database encrypted
        It "Should compress an encrypted db" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance2 -Database encrypted -Compress
            $results.script | Should -BeLike '*D, COMPRESSION,*'
        }
        Remove-DbaDatabase -SqlInstance $global:instance2 -Database encrypted -confirm:$false
        $sqldrop =
        @"
drop certificate MyServerCert
go
drop master key
go
"@
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query $sqldrop -Database Master
    }

    Context "Custom TimeStamp" {
        # Test relies on DateFormat bobob returning bobob as the values aren't interpreted, check here in case .Net rules change
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master -BackupDirectory $DestBackupDir -TimeStampFormat bobob
        It "Should apply the corect custom Timestamp" {
            ($results | Where-Object { $_.BackupPath -like '*bobob*' }).count | Should -Be $results.count
        }
    }

    Context "Test Backup templating" {
        $results = Backup-DbaDatabase -SqlInstance $global:instance1 -Database master, msdb -BackupDirectory $DestBackupDir\dbname\instancename\backuptype\  -BackupFileName dbname-backuptype.bak -ReplaceInName -BuildPath
        It "Should have replaced the markers" {
            $results[0].BackupPath | Should -BeLike "$DestBackupDir\master\$(($global:instance1).split('\')[1])\Full\master-Full.bak"
            $results[1].BackupPath | Should -BeLike "$DestBackupDir\msdb\$(($global:instance1).split('\')[1])\Full\msdb-Full.bak"
        }
    }

    Context "Test Backup templating when db object piped in issue 8100" {
        $results = Get-DbaDatabase -SqlInstance $global:instance1 -Database master,msdb | Backup-DbaDatabase -BackupDirectory $DestBackupDir\db2\dbname\instancename\backuptype\  -BackupFileName dbname-backuptype.bak -ReplaceInName -BuildPath
        It "Should have replaced the markers" {
            $results[0].BackupPath | Should -BeLike "$DestBackupDir\db2\master\$(($global:instance1).split('\')[1])\Full\master-Full.bak"
            $results[1].BackupPath | Should -BeLike "$DestBackupDir\db2\msdb\$(($global:instance1).split('\')[1])\Full\msdb-Full.bak"
        }
    }

    Context "Test Backup Encryption with Certificate" {
        BeforeAll {
            $securePass = ConvertTo-SecureString "TestPassword1" -AsPlainText -Force
            New-DbaDbMasterKey -SqlInstance $global:instance2 -Database Master -SecurePassword $securePass -Confirm:$false -ErrorAction SilentlyContinue
            $cert = New-DbaDbCertificate -SqlInstance $global:instance2 -Database master -Name BackupCertt -Subject BackupCertt
        }

        AfterAll {
            Remove-DbaDbCertificate -SqlInstance $global:instance2 -Database master -Certificate BackupCertt -Confirm:$false
            Remove-DbaDbMasterKey -SqlInstance $global:instance2 -Database Master -Confirm:$false
        }

        It "Should encrypt the backup" {
            $encBackupResults = Backup-DbaDatabase -SqlInstance $global:instance2 -Database master -EncryptionAlgorithm AES128 -EncryptionCertificate BackupCertt -BackupFileName 'encryptiontest.bak' -Description "Encrypted backup"
            $encBackupResults.EncryptorType | Should -Be "CERTIFICATE"
            $encBackupResults.KeyAlgorithm | Should -Be "aes_128"
            Invoke-Command2 -ComputerName $global:instance2 -ScriptBlock { Remove-Item -Path $args[0] } -ArgumentList $encBackupResults.FullName
        }
    }

    Context "Azure works" -Skip:(-not $env:azurepasswd) {
        BeforeAll {
            Get-DbaDatabase -SqlInstance $global:instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase -Confirm:$false
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            if (Get-DbaCredential -SqlInstance $global:instance2 -Name "[$global:azureblob]" ) {
                $server.Query("DROP CREDENTIAL [$global:azureblob]")
            }
            $server.Query("CREATE CREDENTIAL [$global:azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'")
            $server.Query("CREATE DATABASE dbatoolsci_azure")
            if (Get-DbaCredential -SqlInstance $global:instance2 -name dbatools_ci) {
                $server.Query("DROP CREDENTIAL dbatools_ci")
            }
            $server.Query("CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$global:azureblobaccount', SECRET = N'$env:azurelegacypasswd'")
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $global:instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase -Confirm:$false
            $server.Query("DROP CREDENTIAL [$global:azureblob]")
        }

        It "backs up to Azure properly using SHARED ACCESS SIGNATURE" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance2 -AzureBaseUrl $global:azureblob -Database dbatoolsci_azure -BackupFileName dbatoolsci_azure.bak -WithFormat
            $results.Database | Should -Be 'dbatoolsci_azure'
            $results.DeviceType | Should -Be 'URL'
            $results.BackupFile | Should -Be 'dbatoolsci_azure.bak'
        }

        It "backs up to Azure properly using legacy credential" {
            $results = Backup-DbaDatabase -SqlInstance $global:instance2 -AzureBaseUrl $global:azureblob -Database dbatoolsci_azure -BackupFileName dbatoolsci_azure2.bak -WithFormat -AzureCredential dbatools_ci
            $results.Database | Should -Be 'dbatoolsci_azure'
            $results.DeviceType | Should -Be 'URL'
            $results.BackupFile | Should -Be 'dbatoolsci_azure2.bak'
        }
    }
}

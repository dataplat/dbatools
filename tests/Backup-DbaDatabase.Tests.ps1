#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName               = "dbatools",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Backup-DbaDatabase" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Backup-DbaDatabase
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                'SqlInstance',
                'SqlCredential',
                'Database',
                'ExcludeDatabase',
                'Path',
                'FilePath',
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
                'EnableException',
                'EncryptionAlgorithm',
                'EncryptionCertificate',
                'IncrementPrefix',
                'Description'
            )
        }
        It "Should only contain our specific parameters" {
            $actualParameters = $command.Parameters.Keys | Where-Object { $PSItem -notin "WhatIf", "Confirm" }
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $actualParameters | Should -BeNullOrEmpty
        }

        It "Has parameter: <_>" -ForEach $expectedParameters {
            $command | Should -HaveParameter $PSItem
        }
    }
}

Describe "Backup-DbaDatabase" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $DestBackupDir = "$($TestConfig.Temp)\backups"
        if (-Not (Test-Path $DestBackupDir)) {
            New-Item -Type Container -Path $DestBackupDir
        }

        # Write all files to the same backup destination if not otherwise specified
        $PSDefaultParameterValues['Backup-DbaDatabase:BackupDirectory'] = $DestBackupDir

        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        if (Test-Path $DestBackupDir) {
            Remove-Item -Path $DestBackupDir -Force -Recurse
        }
    }

    Context "Properly backups all databases" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1
        }

        It "Should return a database name, specifically master" {
            $results.DatabaseName | Should -Contain 'master'
        }

        It "Should return successful restore for <_.DatabaseName>" -ForEach $results {
            $PSItem.BackupComplete | Should -BeTrue
        }
    }

    Context "Should not backup if database and exclude match" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -Exclude master -WarningAction SilentlyContinue
        }

        It "Should not return object" {
            $results | Should -BeNullOrEmpty
        }
    }

    Context "No database found to backup should raise warning and null output" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database AliceDoesntDBHereAnyMore -WarningAction SilentlyContinue
        }

        It "Should not return object" {
            $results | Should -BeNullOrEmpty
        }

        It "Should return a warning" {
            $WarnVar | Should -BeLike "*No databases match the request for backups*"
        }
    }

    Context "Database should backup 1 database" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master
        }

        It "Database backup object count Should Be 1" {
            $results | Should -HaveCount 1
            $results.BackupComplete | Should -BeTrue
        }

        It "Database ID should be returned" {
            $results.DatabaseID | Should -Be 1
        }
    }

    Context "Database should backup 2 databases" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master, msdb
        }

        It "Database backup object count Should Be 2" {
            $results | Should -HaveCount 2
            $results.BackupComplete | Should -Be @($true, $true)
        }
    }

    Context "Should take path and filename" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -BackupFileName 'PesterTest.bak'
        }

        It "Should report it has backed up to the path with the correct name" {
            $results.FullName | Should -BeLike "$DestBackupDir*PesterTest.bak"
        }

        It "Should have backed up to the path with the correct name" {
            Test-Path "$DestBackupDir\PesterTest.bak" | Should -BeTrue
        }
    }

    Context "Database parameter works when using pipes (fixes #5044)" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 | Backup-DbaDatabase -Database master -BackupFileName PesterTest.bak -WarningAction SilentlyContinue
        }

        It "Should report it has backed up to the path with the correct name" {
            $results.FullName | Should -BeLike "$DestBackupDir*PesterTest.bak"
        }

        It "Should have backed up to the path with the correct name" {
            Test-Path "$DestBackupDir\PesterTest.bak" | Should -BeTrue
        }
    }

    Context "ExcludeDatabase parameter works when using pipes (fixes #5044)" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 | Backup-DbaDatabase -ExcludeDatabase master, tempdb, msdb, model -WarningAction SilentlyContinue
        }

        It "Should report it has backed up to the path with the correct name" {
            $results.DatabaseName | Should -Not -Contain master
            $results.DatabaseName | Should -Not -Contain tempdb
            $results.DatabaseName | Should -Not -Contain msdb
            $results.DatabaseName | Should -Not -Contain model
        }
    }

    Context "Handling backup paths that don't exist (1)" {
        BeforeAll {
            $MissingPath = "$DestBackupDir\Missing1\Awol2"
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -BackupDirectory $MissingPath -WarningAction SilentlyContinue
        }

        It "Should not return object" {
            $results | Should -BeNullOrEmpty
        }

        It "Should warn and fail if path doesn't exist and BuildPath not set" {
            $WarnVar | Should -BeLike "*$MissingPath*"
        }
    }

    Context "Handling backup paths that don't exist (2)" {
        # $MissingPathTrailing has a trailing slash but we normalize the path before doing the actual backup
        BeforeAll {
            $MissingPathTrailing = "$DestBackupDir\Missing1\Awol2\"
            $MissingPath = "$DestBackupDir\Missing1\Awol2"
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -BackupDirectory $MissingPathTrailing -BuildPath -WarningAction SilentlyContinue
        }

        It "Should have backed up to $MissingPath" {
            $results.BackupFolder | Should -Be "$MissingPath"
            $results.Path | Should -Not -BeLike '*\\*'
        }
    }

    Context "CreateFolder switch should append the databasename to the backup path" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -CreateFolder
        }

        It "Should have appended master to the backup path" {
            $results.BackupFolder | Should -Be "$DestBackupDir\master"
        }
    }

    Context "CreateFolder switch should append the databasename to the backup path even when striping" {
        BeforeAll {
            $backupPaths = "$DestBackupDir\stripewithdb1", "$DestBackupDir\stripewithdb2"
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -BackupDirectory $backupPaths -CreateFolder
        }

        It "Should have appended master to all backup paths" {
            foreach ($path in $results.BackupFolder) {
                ($results.BackupFolder | Sort-Object) | Should -Be ($backupPaths | Sort-Object | ForEach-Object { [IO.Path]::Combine($_, 'master') })
            }
        }
    }

    Context "A fully qualified path should override a backupfolder" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -BackupDirectory $TestConfig.Temp -BackupFileName "$DestBackupDir\PesterTest2.bak"
        }

        It "Should report backed up to $DestBackupDir" {
            $results.FullName | Should -BeLike "$DestBackupDir\PesterTest2.bak"
            $results.BackupFolder | Should -Not -Be $TestConfig.Temp
        }

        It "Should have backuped up to $DestBackupDir\PesterTest2.bak" {
            Test-Path "$DestBackupDir\PesterTest2.bak" | Should -Be $true
        }
    }

    Context "Should stripe if multiple backupfolders specified (1)" {
        BeforeAll {
            $backupPaths = "$DestBackupDir\stripe1", "$DestBackupDir\stripe2", "$DestBackupDir\stripe3"
            $null = New-Item -Path $backupPaths -ItemType Directory
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -BackupDirectory $backupPaths
        }

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
    }

    Context "Should stripe if multiple backupfolders specified (2)" {
        # Assure that striping logic favours -BackupDirectory and not -Filecount
        BeforeAll {
            $backupPaths = "$DestBackupDir\stripe1", "$DestBackupDir\stripe2", "$DestBackupDir\stripe3"
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -BackupDirectory $backupPaths -FileCount 2
        }

        It "Should have created 3 backups, even when FileCount is different" {
            $results.BackupFilesCount | Should -Be 3
        }
    }

    Context "Should stripe on filecount > 1" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -FileCount 3
        }

        It "Should have created 3 backups" {
            $results.BackupFilesCount | Should -Be 3
        }

        It "Should have 1 period in file extension" {
            foreach ($path in $results.BackupFile) {
                [IO.Path]::GetExtension($path) | Should -Not -BeLike '*..*'
            }
        }
    }

    Context "Should prefix the filenames when IncrementPrefix set" {
        BeforeAll {
            $fileCount = 3
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -FileCount $fileCount -IncrementPrefix
        }

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
        BeforeAll {
            $PSDefaultParameterValues.Remove('Backup-DbaDatabase:BackupDirectory')
            $defaultBackupPath = (Get-DbaDefaultPath -SqlInstance $TestConfig.instance1).Backup
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -BackupFileName 'PesterTest.bak'
        }

        AfterAll {
            Get-ChildItem -Path $results.FullName | Remove-Item -ErrorAction SilentlyContinue
            $PSDefaultParameterValues['Backup-DbaDatabase:BackupDirectory'] = $DestBackupDir
        }

        It "Should report it has backed up to the path with the corrrect name" {
            $results.FullName | Should -BeLike "$defaultBackupPath*PesterTest.bak"
        }

        It "Should have backed up to the path with the corrrect name" {
            Test-Path "$defaultBackupPath\PesterTest.bak" | Should -BeTrue
        }
    }

    Context "Test backup verification" {
        BeforeAll {
            # "-RecoveryModel Full" only needed on very old versions
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name backuptest -RecoveryModel Full
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database backuptest
        }

        It "Should perform a full backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database backuptest -Type full -Verify
            $b.BackupComplete | Should -BeTrue
            $b.Verified | Should -BeTrue
            $b.count | Should -Be 1
        }

        It "Should perform a diff backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database backuptest -Type diff -Verify
            $b.BackupComplete | Should -BeTrue
            $b.Verified | Should -BeTrue
        }

        It "Should perform a log backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database backuptest -Type log -Verify
            $b.BackupComplete | Should -BeTrue
            $b.Verified | Should -BeTrue
        }
    }

    Context "Backup can pipe to restore" {
        BeforeAll {
            $random = Get-Random
            $DestDbRandom = "dbatools_ci_backupdbadatabase$random"
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance1 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName "dbatoolsci_singlerestore"
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database "dbatoolsci_singlerestore" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName $DestDbRandom -TrustDbBackupHistory -ReplaceDbNameInFile
        }

        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database "dbatoolsci_singlerestore" | Remove-DbaDatabase
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $DestDbRandom | Remove-DbaDatabase
        }

        It "Should return successful restore" {
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Test Backup-DbaDatabase can take pipe input" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master | Backup-DbaDatabase
        }

        It "Should not warn" {
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Should Complete Successfully" {
            $results.BackupComplete | Should -BeTrue
        }
    }

    Context "Should handle NUL as an input path" {
        BeforeAll {
            $PSDefaultParameterValues.Remove('Backup-DbaDatabase:BackupDirectory')
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -BackupFileName NUL
        }

        AfterAll {
            $PSDefaultParameterValues['Backup-DbaDatabase:BackupDirectory'] = $DestBackupDir
        }

        It "Should return succesful backup" {
            $results.BackupComplete | Should -Be $true
        }

        It "Should have backed up to NUL:" {
            $results.FullName[0] | Should -Be 'NUL:'
        }
    }

    Context "Should only output a T-SQL String if OutputScriptOnly specified" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -BackupFileName c:\notexists\file.bak -OutputScriptOnly
        }

        It "Should return a string" {
            $results.GetType().ToString() | Should -Be 'System.String'
        }

        It "Should return BACKUP DATABASE [master] TO  DISK = N'c:\notexists\file.bak' WITH NOFORMAT, NOINIT, NOSKIP, REWIND, NOUNLOAD,  STATS = 1" {
            $results | Should -Be "BACKUP DATABASE [master] TO  DISK = N'c:\notexists\file.bak' WITH NOFORMAT, NOINIT, NOSKIP, REWIND, NOUNLOAD,  STATS = 1"
        }
    }

    Context "Should handle an encrypted database when compression is specified" {
        BeforeAll {
            $sqlencrypt = @"
IF NOT EXISTS (select * from sys.symmetric_keys where name like '%DatabaseMasterKey%') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<StrongPassword>'
go
CREATE CERTIFICATE MyServerCert WITH SUBJECT = 'My DEK Certificate';
go
CREATE DATABASE encrypted
go
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query $sqlencrypt -Database Master
            $createdb = @"
CREATE DATABASE ENCRYPTION KEY
WITH ALGORITHM = AES_128
ENCRYPTION BY SERVER CERTIFICATE MyServerCert;
GO
ALTER DATABASE encrypted
SET ENCRYPTION ON;
GO
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query $createdb -Database encrypted
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database encrypted
            $sqldrop = @"
drop certificate MyServerCert
go
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query $sqldrop -Database Master
        }

        It "Should compress an encrypted db" {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database encrypted -Compress
            Invoke-Command2 -ComputerName $TestConfig.instance2 -ScriptBlock { Remove-Item -Path $args[0] } -ArgumentList $results.FullName
            $results.script | Should -BeLike '*D, COMPRESSION,*'
        }
    }

    Context "Custom TimeStamp" {
        # Test relies on DateFormat bobob returning bobob as the values aren't interpreted, check here in case .Net rules change
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -TimeStampFormat bobob
        }

        It "Should apply the corect custom Timestamp" {
            ($results | Where-Object { $_.BackupPath -like '*bobob*' }).count | Should -Be $results.count
        }
    }

    Context "Test Backup templating" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master, msdb -BackupDirectory $DestBackupDir\dbname\instancename\backuptype\ -BackupFileName dbname-backuptype.bak -ReplaceInName -BuildPath
            $instanceName = ([DbaInstanceParameter]$TestConfig.instance1).InstanceName
        }

        It "Should have replaced the markers" {
            $results[0].BackupPath | Should -BeLike "$DestBackupDir\master\$instanceName\Full\master-Full.bak"
            $results[1].BackupPath | Should -BeLike "$DestBackupDir\msdb\$instanceName\Full\msdb-Full.bak"
        }
    }

    Context "Test Backup templating when db object piped in issue 8100" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master, msdb | Backup-DbaDatabase -BackupDirectory $DestBackupDir\db2\dbname\instancename\backuptype\  -BackupFileName dbname-backuptype.bak -ReplaceInName -BuildPath
            $instanceName = ([DbaInstanceParameter]$TestConfig.instance1).InstanceName
        }

        It "Should have replaced the markers" {
            $results[0].BackupPath | Should -BeLike "$DestBackupDir\db2\master\$instanceName\Full\master-Full.bak"
            $results[1].BackupPath | Should -BeLike "$DestBackupDir\db2\msdb\$instanceName\Full\msdb-Full.bak"
        }
    }

    Context "Test Backup Encryption with Certificate" {
        # TODO: Should the master key be created at lab startup like in instance3?
        BeforeAll {
            $securePass = ConvertTo-SecureString "estBackupDir\master\script:instance1).split('\')[1])\Full\master-Full.bak" -AsPlainText -Force
            New-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database Master -SecurePassword $securePass -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $cert = New-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master -Name BackupCertt -Subject BackupCertt
            $encBackupResults = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database master -EncryptionAlgorithm AES128 -EncryptionCertificate BackupCertt -BackupFileName 'encryptiontest.bak' -Description "Encrypted backup"
            Invoke-Command2 -ComputerName $TestConfig.instance2 -ScriptBlock { Remove-Item -Path $args[0] } -ArgumentList $encBackupResults.FullName
        }

        AfterAll {
            Remove-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master -Certificate BackupCertt
            Remove-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database Master -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        }

        It "Should encrypt the backup" {
            $encBackupResults.EncryptorType | Should -Be "CERTIFICATE"
            $encBackupResults.KeyAlgorithm | Should -Be "aes_128"
        }
    }

    # Context "Test Backup Encryption with Asymmetric Key" {
    #     $key = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Database master -Name BackupKey
    #     $encBackupResults = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database master -EncryptionAlgorithm AES128 -EncryptionKey BackupKey
    #     It "Should encrypt the backup" {
    #         $encBackupResults.EncryptorType | Should Be "CERTIFICATE"
    #         $encBackupResults.KeyAlgorithm | Should Be "aes_128"
    #     }
    #     remove-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master -Certificate BackupCertt
    # }

    if ($env:azurepasswd) {
        Context "Azure works" {
            BeforeAll {
                Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase
                $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
                if (Get-DbaCredential -SqlInstance $TestConfig.instance2 -Name "[$TestConfig.azureblob]" ) {
                    $sql = "DROP CREDENTIAL [$TestConfig.azureblob]"
                    $server.Query($sql)
                }
                $sql = "CREATE CREDENTIAL [$TestConfig.azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
                $server.Query($sql)
                $server.Query("CREATE DATABASE dbatoolsci_azure")
                if (Get-DbaCredential -SqlInstance $TestConfig.instance2 -name dbatools_ci) {
                    $sql = "DROP CREDENTIAL dbatools_ci"
                    $server.Query($sql)
                }
                $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$TestConfig.azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
                $server.Query($sql)
            }

            AfterAll {
                Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase
                $server.Query("DROP CREDENTIAL [$TestConfig.azureblob]")
            }

            It "backs up to Azure properly using SHARED ACCESS SIGNATURE" {
                $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -AzureBaseUrl $TestConfig.azureblob -Database dbatoolsci_azure -BackupFileName dbatoolsci_azure.bak -WithFormat
                $results.Database | Should -Be 'dbatoolsci_azure'
                $results.DeviceType | Should -Be 'URL'
                $results.BackupFile | Should -Be 'dbatoolsci_azure.bak'
            }

            It "backs up to Azure properly using legacy credential" {
                $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -AzureBaseUrl $TestConfig.azureblob -Database dbatoolsci_azure -BackupFileName dbatoolsci_azure2.bak -WithFormat -AzureCredential dbatools_ci
                $results.Database | Should -Be 'dbatoolsci_azure'
                $results.DeviceType | Should -Be 'URL'
                $results.BackupFile | Should -Be 'dbatoolsci_azure2.bak'
            }
        }
    }
}

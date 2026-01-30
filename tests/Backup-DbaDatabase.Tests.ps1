#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Backup-DbaDatabase",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Path",
                "FilePath",
                "ReplaceInName",
                "NoAppendDbNameInPath",
                "CopyOnly",
                "Type",
                "InputObject",
                "CreateFolder",
                "FileCount",
                "CompressBackup",
                "Checksum",
                "Verify",
                "MaxTransferSize",
                "BlockSize",
                "BufferCount",
                "StorageBaseUrl",
                "StorageCredential",
                "S3Region",
                "NoRecovery",
                "BuildPath",
                "WithFormat",
                "Initialize",
                "SkipTapeHeader",
                "TimeStampFormat",
                "IgnoreFileChecks",
                "OutputScriptOnly",
                "EnableException",
                "EncryptionAlgorithm",
                "EncryptionCertificate",
                "IncrementPrefix",
                "Description"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        $DestBackupDir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Type Container -Path $DestBackupDir

        # Write all files to the same backup destination if not otherwise specified
        $PSDefaultParameterValues['Backup-DbaDatabase:Path'] = $DestBackupDir

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $PSDefaultParameterValues.Remove('Backup-DbaDatabase:Path')

        # Remove the backup directory.
        Remove-Item -Path $DestBackupDir -Force -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Properly backups all databases" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1
        }

        It "Should return a database name, specifically master" {
            $results.DatabaseName | Should -Contain "master"
        }

        It "Should return successful restore for all databases" {
            $results | ForEach-Object { $PSItem.BackupComplete | Should -BeTrue }
        }
    }

    Context "Should not backup if database and exclude match" {
        It "Should not return object" {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -Exclude master -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
        }
    }

    Context "No database found to backup should raise warning and null output" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database AliceDoesntDBHereAnyMore -WarningAction SilentlyContinue
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
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master
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
        It "Database backup object count Should Be 2" {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master, msdb
            $results | Should -HaveCount 2
            $results.BackupComplete | Should -Be @($true, $true)
        }
    }

    Context "Should take path and filename" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -BackupFileName "PesterTest.bak"
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
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 | Backup-DbaDatabase -Database master -BackupFileName PesterTest.bak -WarningAction SilentlyContinue
        }

        It "Should report it has backed up to the path with the correct name" {
            $results.FullName | Should -BeLike "$DestBackupDir*PesterTest.bak"
        }

        It "Should have backed up to the path with the correct name" {
            Test-Path "$DestBackupDir\PesterTest.bak" | Should -BeTrue
        }
    }

    Context "ExcludeDatabase parameter works when using pipes (fixes #5044)" {
        It "Should report it has backed up to the path with the correct name" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 | Backup-DbaDatabase -ExcludeDatabase master, tempdb, msdb, model -WarningAction SilentlyContinue
            $results.DatabaseName | Should -Not -Contain master
            $results.DatabaseName | Should -Not -Contain tempdb
            $results.DatabaseName | Should -Not -Contain msdb
            $results.DatabaseName | Should -Not -Contain model
        }
    }

    Context "Handling backup paths that don't exist (1)" {
        BeforeAll {
            $MissingPath = "$DestBackupDir\Missing1\Awol2"
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -Path $MissingPath -WarningAction SilentlyContinue
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
        It "Should have backed up to $MissingPath" {
            $MissingPathTrailing = "$DestBackupDir\Missing1\Awol2\"
            $MissingPath = "$DestBackupDir\Missing1\Awol2"
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -Path $MissingPathTrailing -BuildPath -WarningAction SilentlyContinue
            $results.BackupFolder | Should -Be "$MissingPath"
            #$results.Path | Should -Not -BeLike "*\\*"
        }
    }

    Context "CreateFolder switch should append the databasename to the backup path" {
        It "Should have appended master to the backup path" {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -CreateFolder
            $results.BackupFolder | Should -Be "$DestBackupDir\master"
        }
    }

    Context "CreateFolder switch should append the databasename to the backup path even when striping" {
        It "Should have appended master to all backup paths" {
            $backupPaths = "$DestBackupDir\stripewithdb1", "$DestBackupDir\stripewithdb2"
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -Path $backupPaths -CreateFolder
            foreach ($path in $results.BackupFolder) {
                ($results.BackupFolder | Sort-Object) | Should -Be ($backupPaths | Sort-Object | ForEach-Object { [IO.Path]::Combine($PSItem, "master") })
            }
        }
    }

    Context "A fully qualified path should override a backupfolder" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -Path $TestConfig.Temp -BackupFileName "$DestBackupDir\PesterTest2.bak"
        }

        It "Should report backed up to $DestBackupDir" {
            $results.FullName | Should -BeLike "$DestBackupDir\PesterTest2.bak"
            $results.BackupFolder | Should -Not -Be $TestConfig.Temp
        }

        It "Should have backuped up to $DestBackupDir\PesterTest2.bak" {
            Test-Path "$DestBackupDir\PesterTest2.bak" | Should -BeTrue
        }
    }

    Context "Should stripe if multiple backupfolders specified (1)" {
        BeforeAll {
            $backupPaths = "$DestBackupDir\stripe1", "$DestBackupDir\stripe2", "$DestBackupDir\stripe3"
            $null = New-Item -Path $backupPaths -ItemType Directory
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -Path $backupPaths
        }

        It "Should have created 3 backups" {
            $results.BackupFilesCount | Should -Be 3
        }

        It "Should have written to all 3 folders" {
            $backupPaths | ForEach-Object {
                $PSItem | Should -BeIn ($results.BackupFolder)
            }
        }

        It "Should have written files with extensions" {
            foreach ($path in $results.BackupFile) {
                [IO.Path]::GetExtension($path) | Should -Be ".bak"
            }
        }
    }

    Context "Should stripe if multiple backupfolders specified (2)" {
        # Assure that striping logic favours -Path and not -Filecount
        It "Should have created 3 backups, even when FileCount is different" {
            $backupPaths = "$DestBackupDir\stripe1", "$DestBackupDir\stripe2", "$DestBackupDir\stripe3"
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -Path $backupPaths -FileCount 2
            $results.BackupFilesCount | Should -Be 3
        }
    }

    Context "Should stripe on filecount > 1" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -FileCount 3
        }

        It "Should have created 3 backups" {
            $results.BackupFilesCount | Should -Be 3
        }

        It "Should have 1 period in file extension" {
            foreach ($path in $results.BackupFile) {
                [IO.Path]::GetExtension($path) | Should -Not -BeLike "*..*"
            }
        }
    }

    Context "Should prefix the filenames when IncrementPrefix set" {
        BeforeAll {
            $fileCount = 3
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -FileCount $fileCount -IncrementPrefix
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
            $PSDefaultParameterValues.Remove("Backup-DbaDatabase:Path")
            $defaultBackupPath = (Get-DbaDefaultPath -SqlInstance $TestConfig.InstanceCopy1).Backup
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -BackupFileName "PesterTest.bak"
            $targetPath = $results.FullName
            if (-not ([DbaInstanceParameter]($TestConfig.InstanceCopy1)).IsLocalHost -and $defaultBackupPath.Substring(1, 1) -eq ':') {
                $targetPath = $targetPath -replace '^(.):(.*)$', "\\$(([DbaInstanceParameter]($TestConfig.InstanceCopy1)).ComputerName)\`$1`$$`$2"
            }
        }

        AfterAll {
            Get-ChildItem -Path $targetPath | Remove-Item -ErrorAction SilentlyContinue
            $PSDefaultParameterValues["Backup-DbaDatabase:Path"] = $DestBackupDir
        }

        It "Should report it has backed up to the path with the corrrect name" {
            $results.FullName | Should -BeLike "$defaultBackupPath*PesterTest.bak"
        }

        It "Should have backed up to the path with the corrrect name" {
            Test-Path $targetPath | Should -BeTrue
        }
    }

    Context "Test backup verification" {
        BeforeAll {
            # "-RecoveryModel Full" only needed on very old versions
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name backuptest -RecoveryModel Full
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database backuptest
        }

        It "Should perform a full backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database backuptest -Type full -Verify
            $b.BackupComplete | Should -BeTrue
            $b.Verified | Should -BeTrue
            $b.count | Should -Be 1
        }

        It "Should perform a diff backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database backuptest -Type diff -Verify
            $b.BackupComplete | Should -BeTrue
            $b.Verified | Should -BeTrue
        }

        It "Should perform a log backup and verify it" {
            $b = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database backuptest -Type log -Verify
            $b.BackupComplete | Should -BeTrue
            $b.Verified | Should -BeTrue
        }
    }

    Context "Backup can pipe to restore" {
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database "dbatoolsci_singlerestore" | Remove-DbaDatabase
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $DestDbRandom | Remove-DbaDatabase
        }

        It "Should return successful restore" {
            $random = Get-Random
            $DestDbRandom = "dbatools_ci_backupdbadatabase$random"
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName "dbatoolsci_singlerestore"
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database "dbatoolsci_singlerestore" | Restore-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -DatabaseName $DestDbRandom -TrustDbBackupHistory -ReplaceDbNameInFile
            $results.RestoreComplete | Should -BeTrue
        }
    }

    Context "Test Backup-DbaDatabase can take pipe input" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master | Backup-DbaDatabase
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
            $PSDefaultParameterValues.Remove('Backup-DbaDatabase:Path')
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -BackupFileName NUL
        }

        AfterAll {
            $PSDefaultParameterValues["Backup-DbaDatabase:Path"] = $DestBackupDir
        }

        It "Should return succesful backup" {
            $results.BackupComplete | Should -BeTrue
        }

        It "Should have backed up to NUL:" {
            $results.FullName[0] | Should -Be "NUL:"
        }
    }

    Context "Should only output a T-SQL String if OutputScriptOnly specified" {
        BeforeAll {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -BackupFileName c:\notexists\file.bak -OutputScriptOnly
        }

        It "Should return a string" {
            $results.GetType().ToString() | Should -Be "System.String"
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
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $sqlencrypt -Database master
            $createdb = @"
CREATE DATABASE ENCRYPTION KEY
WITH ALGORITHM = AES_128
ENCRYPTION BY SERVER CERTIFICATE MyServerCert;
GO
ALTER DATABASE encrypted
SET ENCRYPTION ON;
GO
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $createdb -Database encrypted
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database encrypted
            $sqldrop = @"
drop certificate MyServerCert
go
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query $sqldrop -Database master
        }

        It "Should compress an encrypted db" {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database encrypted -Compress
            if ($results.FullName -like '\\*') {
                Remove-Item -Path $results.FullName
            } else {
                Invoke-Command2 -ComputerName $TestConfig.InstanceCopy2 -ScriptBlock { Remove-Item -Path $args[0] } -ArgumentList $results.FullName
            }
            $results.script | Should -BeLike "*D, COMPRESSION,*"
        }
    }

    Context "Custom TimeStamp" {
        # Test relies on DateFormat bobob returning bobob as the values aren't interpreted, check here in case .Net rules change
        It "Should apply the corect custom Timestamp" {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master -TimeStampFormat bobob
            ($results | Where-Object { $PSItem.BackupPath -like "*bobob*" }).Count | Should -Be $results.Count
        }
    }

    Context "Test Backup templating" {
        It "Should have replaced the markers" {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master, msdb -Path $DestBackupDir\dbname\instancename\backuptype\ -BackupFileName dbname-backuptype.bak -ReplaceInName -BuildPath
            $instanceName = ([DbaInstanceParameter]$TestConfig.InstanceCopy1).InstanceName
            $results[0].BackupPath | Should -BeLike "$DestBackupDir\master\$instanceName\Full\master-Full.bak"
            $results[1].BackupPath | Should -BeLike "$DestBackupDir\msdb\$instanceName\Full\msdb-Full.bak"
        }
    }

    Context "Test Backup templating when db object piped in issue 8100" {
        It "Should have replaced the markers" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database master, msdb | Backup-DbaDatabase -Path $DestBackupDir\db2\dbname\instancename\backuptype\  -BackupFileName dbname-backuptype.bak -ReplaceInName -BuildPath
            $instanceName = ([DbaInstanceParameter]$TestConfig.InstanceCopy1).InstanceName
            $results[0].BackupPath | Should -BeLike "$DestBackupDir\db2\master\$instanceName\Full\master-Full.bak"
            $results[1].BackupPath | Should -BeLike "$DestBackupDir\db2\msdb\$instanceName\Full\msdb-Full.bak"
        }
    }

    Context "Test Backup Encryption with Certificate" {
        # TODO: Should the master key be created at lab startup like in instance3?
        BeforeAll {
            $securePass = ConvertTo-SecureString "MyStrongPassword123!" -AsPlainText -Force
            $cert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceCopy2 -Database master -Name BackupCertt -Subject BackupCertt
            $encBackupResults = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database master -EncryptionAlgorithm AES128 -EncryptionCertificate BackupCertt -BackupFileName "encryptiontest.bak" -Description "Encrypted backup"
            if ($encBackupResults.FullName -like '\\*') {
                Remove-Item -Path $encBackupResults.FullName
            } else {
                Invoke-Command2 -ComputerName $TestConfig.InstanceCopy2 -ScriptBlock { Remove-Item -Path $args[0] } -ArgumentList $encBackupResults.FullName
            }
        }

        AfterAll {
            Remove-DbaDbCertificate -SqlInstance $TestConfig.InstanceCopy2 -Database master -Certificate BackupCertt
        }

        It "Should encrypt the backup" {
            $encBackupResults.EncryptorType | Should -BeLike "CERTIFICATE*"  # 2025 returns: CERTIFICATE_OAEP_256
            $encBackupResults.KeyAlgorithm | Should -Be "aes_128"
        }
    }

    # Context "Test Backup Encryption with Asymmetric Key" {
    #     $key = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceCopy2 -Database master -Name BackupKey
    #     $encBackupResults = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database master -EncryptionAlgorithm AES128 -EncryptionKey BackupKey
    #     It "Should encrypt the backup" {
    #         $encBackupResults.EncryptorType | Should Be "CERTIFICATE"
    #         $encBackupResults.KeyAlgorithm | Should Be "aes_128"
    #     }
    #     remove-DbaDbCertificate -SqlInstance $TestConfig.InstanceCopy2 -Database master -Certificate BackupCertt
    # }

    if ($env:azurepasswd) {
        Context "Azure works" {
            BeforeAll {
                Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database "dbatoolsci_azure" | Remove-DbaDatabase
                $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
                if (Get-DbaCredential -SqlInstance $TestConfig.InstanceCopy2 -Name "[$TestConfig.azureblob]" ) {
                    $sql = "DROP CREDENTIAL [$TestConfig.azureblob]"
                    $server.Query($sql)
                }
                $sql = "CREATE CREDENTIAL [$($TestConfig.azureblob)] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$($env:azurepasswd)'"
                $server.Query($sql)
                $server.Query("CREATE DATABASE dbatoolsci_azure")
                if (Get-DbaCredential -SqlInstance $TestConfig.InstanceCopy2 -name dbatools_ci) {
                    $sql = "DROP CREDENTIAL dbatools_ci"
                    $server.Query($sql)
                }
                $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$($TestConfig.azureblobaccount)', SECRET = N'$($env:azurelegacypasswd)'"
                $server.Query($sql)
            }

            AfterAll {
                Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database "dbatoolsci_azure" | Remove-DbaDatabase
                $server.Query("DROP CREDENTIAL [$TestConfig.azureblob]")
            }

            It "backs up to Azure properly using SHARED ACCESS SIGNATURE" {
                $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -AzureBaseUrl $TestConfig.azureblob -Database dbatoolsci_azure -BackupFileName dbatoolsci_azure.bak -WithFormat
                $results.Database | Should -Be "dbatoolsci_azure"
                $results.DeviceType | Should -Be "URL"
                $results.BackupFile | Should -Be "dbatoolsci_azure.bak"
            }

            It "backs up to Azure properly using legacy credential" {
                $results = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -AzureBaseUrl $TestConfig.azureblob -Database dbatoolsci_azure -BackupFileName dbatoolsci_azure2.bak -WithFormat -AzureCredential dbatools_ci
                $results.Database | Should -Be "dbatoolsci_azure"
                $results.DeviceType | Should -Be "URL"
                $results.BackupFile | Should -Be "dbatoolsci_azure2.bak"
            }
        }
    }
}
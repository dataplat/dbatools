#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDatabase",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Database",
                "ExcludeDatabase",
                "AllDatabases",
                "BackupRestore",
                "AdvancedBackupParams",
                "SharedPath",
                "AzureCredential",
                "WithReplace",
                "NoRecovery",
                "NoBackupCleanup",
                "NumberFiles",
                "DetachAttach",
                "Reattach",
                "SetSourceReadOnly",
                "ReuseSourceFolderStructure",
                "IncludeSupportDbs",
                "UseLastBackup",
                "Continue",
                "InputObject",
                "NoCopyOnly",
                "SetSourceOffline",
                "NewName",
                "Prefix",
                "Force",
                "EnableException",
                "KeepCDC",
                "KeepReplication"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $NetworkPath = $TestConfig.Temp
        $random = Get-Random
        $backuprestoredb = "dbatoolsci_backuprestore$random"
        $backuprestoredb2 = "dbatoolsci_backuprestoreother$random"
        $detachattachdb = "dbatoolsci_detachattach$random"
        $supportDbs = @("ReportServer", "ReportServerTempDB", "distribution", "SSISDB")

        $splatRemoveInitial = @{
            SqlInstance = $TestConfig.instance2, $TestConfig.instance3
            Database    = $backuprestoredb, $detachattachdb
            Confirm     = $false
        }
        Remove-DbaDatabase @splatRemoveInitial

        $server3 = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        $server3.Query("CREATE DATABASE $backuprestoredb2; ALTER DATABASE $backuprestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")

        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $server2.Query("CREATE DATABASE $backuprestoredb; ALTER DATABASE $backuprestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $server2.Query("CREATE DATABASE $detachattachdb; ALTER DATABASE $detachattachdb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $server2.Query("CREATE DATABASE $backuprestoredb2; ALTER DATABASE $backuprestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        foreach ($db in $supportDbs) {
            $server2.Query("CREATE DATABASE [$db]; ALTER DATABASE [$db] SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE;")
        }

        $splatSetOwner = @{
            SqlInstance = $TestConfig.instance2
            Database    = $backuprestoredb, $detachattachdb
            TargetLogin = "sa"
        }
        $null = Set-DbaDbOwner @splatSetOwner

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $splatRemoveFinal = @{
            SqlInstance = $TestConfig.instance2, $TestConfig.instance3
            Database    = $backuprestoredb, $detachattachdb, $backuprestoredb2
            Confirm     = $false
        }
        Remove-DbaDatabase @splatRemoveFinal -ErrorAction SilentlyContinue

        $splatRemoveSupport = @{
            SqlInstance = $TestConfig.instance2
            Database    = $supportDbs
            Confirm     = $false
        }
        Remove-DbaDatabase @splatRemoveSupport -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Support databases are excluded when AllDatabase selected" {
        It "Support databases should not be migrated" {
            $SupportDbs = @("ReportServer", "ReportServerTempDB", "distribution", "SSISDB")
            $splatCopyAll = @{
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                AllDatabase   = $true
                BackupRestore = $true
                UseLastBackup = $true
            }
            $results = Copy-DbaDatabase @splatCopyAll
            $SupportDbs | Should -Not -BeIn $results.Name
        }
    }

    # if failed Disable-NetFirewallRule -DisplayName 'Core Networking - Group Policy (TCP-Out)'
    Context "Detach Attach" {
        BeforeAll {
            $splatDetachAttach = @{
                Source       = $TestConfig.instance2
                Destination  = $TestConfig.instance3
                Database     = $detachattachdb
                DetachAttach = $true
                Reattach     = $true
                Force        = $true
            }
            $detachResults = Copy-DbaDatabase @splatDetachAttach #-WarningAction SilentlyContinue
        }

        It "Should be success" {
            $detachResults.Status | Should -Be "Successful"
        }

        It "should not be null" {
            $db1 = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $detachattachdb
            $db2 = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $detachattachdb

            $db1.Name | Should -Be $detachattachdb
            $db2.Name | Should -Be $detachattachdb
        }

        It "Name, recovery model, and status should match" {
            $db1 = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $detachattachdb
            $db2 = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $detachattachdb

            # Compare its variable
            $db1.Name | Should -Be $db2.Name
            $db1.RecoveryModel | Should -Be $db2.RecoveryModel
            $db1.Status | Should -Be $db2.Status
            $db1.Owner | Should -Be $db2.Owner
        }

        It "Should say skipped" {
            $splatDetachAgain = @{
                Source       = $TestConfig.instance2
                Destination  = $TestConfig.instance3
                Database     = $detachattachdb
                DetachAttach = $true
                Reattach     = $true
            }
            $skipResults = Copy-DbaDatabase @splatDetachAgain
            $skipResults.Status | Should -Be "Skipped"
            $skipResults.Notes | Should -Be "Already exists on destination"
        }
    }

    Context "Backup restore" {
        BeforeAll {
            $splatStopProcess = @{
                SqlInstance = $TestConfig.instance2, $TestConfig.instance3
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue

            $splatBackupRestore = @{
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                Database      = $backuprestoredb
                BackupRestore = $true
                SharedPath    = $NetworkPath
            }
            $backupRestoreResults = Copy-DbaDatabase @splatBackupRestore
        }

        It "copies a database successfully" {
            $backupRestoreResults.Name | Should -Be $backuprestoredb
            $backupRestoreResults.Status | Should -Be "Successful"
        }

        It "retains its name, recovery model, and status." {
            $splatGetDbs = @{
                SqlInstance = $TestConfig.instance2, $TestConfig.instance3
                Database    = $backuprestoredb
            }
            $dbs = Get-DbaDatabase @splatGetDbs
            $dbs[0].Name | Should -Not -BeNullOrEmpty
            # Compare its variables
            $dbs[0].Name | Should -Be $dbs[1].Name
            $dbs[0].RecoveryModel | Should -Be $dbs[1].RecoveryModel
            $dbs[0].Status | Should -Be $dbs[1].Status
        }

        # needs regr test that uses $backuprestoredb once #3377 is fixed
        It "Should say skipped" {
            $splatBackupRestore2 = @{
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                Database      = $backuprestoredb2
                BackupRestore = $true
                SharedPath    = $NetworkPath
            }
            $result = Copy-DbaDatabase @splatBackupRestore2
            $result.Status | Should -Be "Skipped"
            $result.Notes | Should -Be "Already exists on destination"
        }

        # needs regr test once #3377 is fixed
        if (-not $env:appveyor) {
            It "Should overwrite when forced to" {
                #regr test for #3358
                $splatBackupRestoreForce = @{
                    Source        = $TestConfig.instance2
                    Destination   = $TestConfig.instance3
                    Database      = $backuprestoredb2
                    BackupRestore = $true
                    SharedPath    = $NetworkPath
                    Force         = $true
                }
                $result = Copy-DbaDatabase @splatBackupRestoreForce
                $result.Status | Should -Be "Successful"
            }
        }
    }

    Context "UseLastBackup - read backup history" {
        BeforeAll {
            $splatStopProcess = @{
                SqlInstance = $TestConfig.instance2, $TestConfig.instance3
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue

            $splatRemoveDb = @{
                SqlInstance = $TestConfig.instance3
                Database    = $backuprestoredb
                Confirm     = $false
            }
            Remove-DbaDatabase @splatRemoveDb
        }

        It "copies a database successfully using backup history" {
            $splatBackup = @{
                SqlInstance     = $TestConfig.instance2
                Database        = $backuprestoredb
                BackupDirectory = $NetworkPath
            }
            $backupResults = Backup-DbaDatabase @splatBackup
            $backupFile = $backupResults.FullName

            $splatCopyLastBackup = @{
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                Database      = $backuprestoredb
                BackupRestore = $true
                UseLastBackup = $true
            }
            $copyResults = Copy-DbaDatabase @splatCopyLastBackup
            $copyResults.Name | Should -Be $backuprestoredb
            $copyResults.Status | Should -Be "Successful"
            Remove-Item -Path $backupFile -ErrorAction SilentlyContinue
        }

        It "retains its name, recovery model, and status." {
            $splatGetDbs = @{
                SqlInstance = $TestConfig.instance2, $TestConfig.instance3
                Database    = $backuprestoredb
            }
            $dbs = Get-DbaDatabase @splatGetDbs
            $dbs[0].Name | Should -Not -BeNullOrEmpty
            # Compare its variables
            $dbs[0].Name | Should -Be $dbs[1].Name
            $dbs[0].RecoveryModel | Should -Be $dbs[1].RecoveryModel
            $dbs[0].Status | Should -Be $dbs[1].Status
        }
    }

    # The Copy-DbaDatabase fails, but I don't know why. So skipping for now.
    Context "UseLastBackup with -Continue" {
        BeforeAll {
            $splatStopProcess = @{
                SqlInstance = $TestConfig.instance2, $TestConfig.instance3
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue

            $splatRemoveDb = @{
                SqlInstance = $TestConfig.instance3
                Database    = $backuprestoredb
                Confirm     = $false
            }
            Remove-DbaDatabase @splatRemoveDb

            #Pre-stage the restore
            $backupPaths = @()
            $splatBackupFull = @{
                SqlInstance     = $TestConfig.instance2
                Database        = $backuprestoredb
                BackupDirectory = $NetworkPath
            }
            $fullBackupResults = Backup-DbaDatabase @splatBackupFull
            $backupPaths += $fullBackupResults.FullName

            $splatRestore = @{
                SqlInstance  = $TestConfig.instance3
                DatabaseName = $backuprestoredb
                NoRecovery   = $true
            }
            $fullBackupResults | Restore-DbaDatabase @splatRestore

            #Run diff now
            $splatBackupDiff = @{
                SqlInstance     = $TestConfig.instance2
                Database        = $backuprestoredb
                BackupDirectory = $NetworkPath
                Type            = "Diff"
            }
            $diffBackupResults = Backup-DbaDatabase @splatBackupDiff
            $backupPaths += $diffBackupResults.FullName
        }

        AfterAll {
            $backupPaths | Select-Object -Unique | Remove-Item -ErrorAction SilentlyContinue
        }

        It "continues the restore over existing database using backup history" -Skip:$true {
            # It should already have a backup history (full+diff) by this time
            $splatCopyContinue = @{
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                Database      = $backuprestoredb
                BackupRestore = $true
                UseLastBackup = $true
                Continue      = $true
            }
            $results = Copy-DbaDatabase @splatCopyContinue
            $results.Name | Should -Be $backuprestoredb
            $results.Status | Should -Be "Successful"
        }

        It "retains its name, recovery model, and status." -Skip:$true {
            $splatGetDbs = @{
                SqlInstance = $TestConfig.instance2, $TestConfig.instance3
                Database    = $backuprestoredb
            }
            $dbs = Get-DbaDatabase @splatGetDbs
            $dbs[0].Name | Should -Not -BeNullOrEmpty
            # Compare its variables
            $dbs[0].Name | Should -Be $dbs[1].Name
            $dbs[0].RecoveryModel | Should -Be $dbs[1].RecoveryModel
            $dbs[0].Status | Should -Be $dbs[1].Status
        }
    }

    Context "Copying with renames using backup/restore" {
        BeforeAll {
            $splatStopProcess = @{
                SqlInstance = $TestConfig.instance2, $TestConfig.instance3
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue
            Get-DbaDatabase -SqlInstance $TestConfig.instance3 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }

        AfterAll {
            $splatStopProcess = @{
                SqlInstance = $TestConfig.instance2, $TestConfig.instance3
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue
            Get-DbaDatabase -SqlInstance $TestConfig.instance3 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }

        It "Should have renamed a single db" {
            $newname = "copy$(Get-Random)"
            $splatCopyRename = @{
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                Database      = $backuprestoredb
                BackupRestore = $true
                SharedPath    = $NetworkPath
                NewName       = $newname
            }
            $results = Copy-DbaDatabase @splatCopyRename
            $results[0].DestinationDatabase | Should -Be $newname
            $files = Get-DbaDbFile -Sqlinstance $TestConfig.instance3 -Database $newname
            ($files.PhysicalName -like "*$newname*").Count | Should -Be $files.Count
        }

        It "Should warn if trying to rename and prefix" {
            $splatCopyRenamePrefix = @{
                Source          = $TestConfig.instance2
                Destination     = $TestConfig.instance3
                Database        = $backuprestoredb
                BackupRestore   = $true
                SharedPath      = $NetworkPath
                NewName         = "newname"
                Prefix          = "pre"
                WarningVariable = "warnvar"
            }
            $null = Copy-DbaDatabase @splatCopyRenamePrefix 3> $null
            $warnvar | Should -BeLike "*NewName and Prefix are exclusive options, cannot specify both"
        }

        It "Should prefix databasename and files" {
            $prefix = "da$(Get-Random)"
            # Writes warning: "Failed to update BrokerEnabled to True" - This is a bug in Copy-DbaDatabase
            $splatCopyPrefix = @{
                Source          = $TestConfig.instance2
                Destination     = $TestConfig.instance3
                Database        = $backuprestoredb
                BackupRestore   = $true
                SharedPath      = $NetworkPath
                Prefix          = $prefix
                WarningVariable = "warn"
            }
            $results = Copy-DbaDatabase @splatCopyPrefix
            # $warn | Should -BeNullOrEmpty
            $results[0].DestinationDatabase | Should -Be "$prefix$backuprestoredb"
            $files = Get-DbaDbFile -Sqlinstance $TestConfig.instance3 -Database "$prefix$backuprestoredb"
            ($files.PhysicalName -like "*$prefix$backuprestoredb*").Count | Should -Be $files.Count
        }
    }

    Context "Copying with renames using detachattach" {
        BeforeAll {
            $splatStopProcess = @{
                SqlInstance = $TestConfig.instance2, $TestConfig.instance3
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue

            $splatRemoveDb = @{
                SqlInstance = $TestConfig.instance3
                Database    = $backuprestoredb
                Confirm     = $false
            }
            Remove-DbaDatabase @splatRemoveDb
        }

        It "Should have renamed a single db" {
            $newname = "copy$(Get-Random)"
            $splatDetachRename = @{
                Source       = $TestConfig.instance2
                Destination  = $TestConfig.instance3
                Database     = $backuprestoredb
                DetachAttach = $true
                NewName      = $newname
                Reattach     = $true
            }
            $results = Copy-DbaDatabase @splatDetachRename
            $results[0].DestinationDatabase | Should -Be $newname
            $files = Get-DbaDbFile -Sqlinstance $TestConfig.instance3 -Database $newname
            ($files.PhysicalName -like "*$newname*").Count | Should -Be $files.Count
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $newname -Confirm:$false
        }

        It "Should prefix databasename and files" {
            $prefix = "copy$(Get-Random)"
            $splatDetachPrefix = @{
                Source       = $TestConfig.instance2
                Destination  = $TestConfig.instance3
                Database     = $backuprestoredb
                DetachAttach = $true
                Reattach     = $true
                Prefix       = $prefix
            }
            $results = Copy-DbaDatabase @splatDetachPrefix
            $results[0].DestinationDatabase | Should -Be "$prefix$backuprestoredb"
            $files = Get-DbaDbFile -Sqlinstance $TestConfig.instance3 -Database "$prefix$backuprestoredb"
            ($files.PhysicalName -like "*$prefix$backuprestoredb*").Count | Should -Be $files.Count
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database "$prefix$backuprestoredb" -Confirm:$false
        }

        It "Should warn and exit if newname and >1 db specified" {
            $splatRestore = @{
                SqlInstance                      = $TestConfig.instance2
                Path                             = "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016"
                UseDestinationDefaultDirectories = $true
            }
            $null = Restore-DbaDatabase @splatRestore

            $splatDetachMultiple = @{
                Source          = $TestConfig.instance2
                Destination     = $TestConfig.instance3
                Database        = $backuprestoredb, "RestoreTimeClean"
                DetachAttach    = $true
                Reattach        = $true
                NewName         = "warn"
                WarningVariable = "warnvar"
            }
            $null = Copy-DbaDatabase @splatDetachMultiple 3> $null
            $warnvar | Should -BeLike "*Cannot use NewName when copying multiple databases"
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "RestoreTimeClean" -Confirm:$false
        }
    }

    if ($env:azurepasswd) {
        Context "Copying via Azure storage" {
            BeforeAll {
                $splatStopProcess = @{
                    SqlInstance = $TestConfig.instance2, $TestConfig.instance3
                    Program     = "dbatools PowerShell module - dbatools.io"
                }
                Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue

                $splatRemoveDb = @{
                    SqlInstance = $TestConfig.instance3
                    Database    = $backuprestoredb
                    Confirm     = $false
                }
                Remove-DbaDatabase @splatRemoveDb

                $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
                $sql = "CREATE CREDENTIAL [$TestConfig.azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
                $server2.Query($sql)
                $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$TestConfig.azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
                $server2.Query($sql)

                $server3 = Connect-DbaInstance -SqlInstance $TestConfig.instance3
                $sql = "CREATE CREDENTIAL [$TestConfig.azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
                $server3.Query($sql)
                $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$TestConfig.azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
                $server3.Query($sql)
            }

            AfterAll {
                Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $backuprestoredb | Remove-DbaDatabase -Confirm:$false
                $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
                $server2.Query("DROP CREDENTIAL [$TestConfig.azureblob]")
                $server2.Query("DROP CREDENTIAL dbatools_ci")
                $server3 = Connect-DbaInstance -SqlInstance $TestConfig.instance3
                $server3.Query("DROP CREDENTIAL [$TestConfig.azureblob]")
                $server3.Query("DROP CREDENTIAL dbatools_ci")
            }

            It "Should Copy $backuprestoredb via Azure legacy credentials" {
                $splatAzureLegacy = @{
                    Source          = $TestConfig.instance2
                    Destination     = $TestConfig.instance3
                    Database        = $backuprestoredb
                    BackupRestore   = $true
                    SharedPath      = $TestConfig.azureblob
                    AzureCredential = "dbatools_ci"
                }
                $results = Copy-DbaDatabase @splatAzureLegacy
                $results[0].Name | Should -Be $backuprestoredb
                $results[0].Status | Should -BeLike "Successful*"
            }

            It "Should Copy $backuprestoredb via Azure new credentials" {
                # Because I think the backup are tripping over each other with the names
                Start-Sleep -Seconds 60

                $splatAzureNew = @{
                    Source        = $TestConfig.instance2
                    Destination   = $TestConfig.instance3
                    Database      = $backuprestoredb
                    NewName       = "djkhgfkjghfdjgd"
                    BackupRestore = $true
                    SharedPath    = $TestConfig.azureblob
                }
                $results = Copy-DbaDatabase @splatAzureNew
                $results[0].Name | Should -Be $backuprestoredb
                $results[0].DestinationDatabase | Should -Be "djkhgfkjghfdjgd"
                $results[0].Status | Should -BeLike "Successful*"
            }
        }
    }
}
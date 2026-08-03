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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $NetworkPath = $TestConfig.Temp
        $random = Get-Random
        $backuprestoredb = "dbatoolsci_backuprestore$random"
        $backuprestoredb2 = "dbatoolsci_backuprestoreother$random"
        $detachattachdb = "dbatoolsci_detachattach$random"
        $supportDbs = @("ReportServer", "ReportServerTempDB", "distribution", "SSISDB")

        $splatRemoveInitial = @{
            SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
            Database    = $backuprestoredb, $detachattachdb
        }
        Remove-DbaDatabase @splatRemoveInitial

        $server3 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $server3.Query("CREATE DATABASE $backuprestoredb2; ALTER DATABASE $backuprestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")

        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $server2.Query("CREATE DATABASE $backuprestoredb; ALTER DATABASE $backuprestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $server2.Query("CREATE DATABASE $detachattachdb; ALTER DATABASE $detachattachdb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $server2.Query("CREATE DATABASE $backuprestoredb2; ALTER DATABASE $backuprestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        # The support databases are real names, not dbatoolsci_ fixtures: a lab instance that hosts
        # replication already owns 'distribution', and creating over it kills the whole Describe.
        # Only the ones this run creates may be dropped again - see the AfterAll.
        $createdSupportDbs = @()
        foreach ($db in $supportDbs) {
            if ($server2.Databases[$db]) {
                continue
            }
            $server2.Query("CREATE DATABASE [$db]; ALTER DATABASE [$db] SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE;")
            $createdSupportDbs += $db
        }

        $splatSetOwner = @{
            SqlInstance = $TestConfig.InstanceCopy1
            Database    = $backuprestoredb, $detachattachdb
            TargetLogin = "sa"
        }
        $null = Set-DbaDbOwner @splatSetOwner

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatRemoveFinal = @{
            SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
            Database    = $backuprestoredb, $detachattachdb, $backuprestoredb2
        }
        Remove-DbaDatabase @splatRemoveFinal -ErrorAction SilentlyContinue

        if ($createdSupportDbs) {
            $splatRemoveSupport = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = $createdSupportDbs
            }
            Remove-DbaDatabase @splatRemoveSupport -ErrorAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Support databases are excluded when AllDatabase selected" {
        It "Support databases should not be migrated" {
            $SupportDbs = @("ReportServer", "ReportServerTempDB", "distribution", "SSISDB")
            $splatCopyAll = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
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
                Source       = $TestConfig.InstanceCopy1
                Destination  = $TestConfig.InstanceCopy2
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
            $db1 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $detachattachdb
            $db2 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $detachattachdb

            $db1.Name | Should -Be $detachattachdb
            $db2.Name | Should -Be $detachattachdb
        }

        It "Name, recovery model, and status should match" {
            $db1 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $detachattachdb
            $db2 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $detachattachdb

            # Compare its variable
            $db1.Name | Should -Be $db2.Name
            $db1.RecoveryModel | Should -Be $db2.RecoveryModel
            $db1.Status | Should -Be $db2.Status
            $db1.Owner | Should -Be $db2.Owner
        }

        It "Should say skipped" {
            $splatDetachAgain = @{
                Source       = $TestConfig.InstanceCopy1
                Destination  = $TestConfig.InstanceCopy2
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
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue

            $splatBackupRestore = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
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
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
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
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
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
                    Source        = $TestConfig.InstanceCopy1
                    Destination   = $TestConfig.InstanceCopy2
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
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue

            $splatRemoveDb = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = $backuprestoredb
            }
            Remove-DbaDatabase @splatRemoveDb
        }

        It "copies a database successfully using backup history" {
            $splatBackup = @{
                SqlInstance     = $TestConfig.InstanceCopy1
                Database        = $backuprestoredb
                BackupDirectory = $NetworkPath
            }
            $backupResults = Backup-DbaDatabase @splatBackup
            $backupFile = $backupResults.FullName

            $splatCopyLastBackup = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
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
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
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

    Context "UseLastBackup with -Continue" {
        BeforeAll {
            $splatStopProcess = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue

            $splatRemoveDb = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = $backuprestoredb
            }
            Remove-DbaDatabase @splatRemoveDb

            #Pre-stage the restore
            $backupPaths = @()
            $splatBackupFull = @{
                SqlInstance     = $TestConfig.InstanceCopy1
                Database        = $backuprestoredb
                BackupDirectory = $NetworkPath
            }
            $fullBackupResults = Backup-DbaDatabase @splatBackupFull
            $backupPaths += $fullBackupResults.FullName

            $splatRestore = @{
                SqlInstance  = $TestConfig.InstanceCopy2
                DatabaseName = $backuprestoredb
                NoRecovery   = $true
            }
            $fullBackupResults | Restore-DbaDatabase @splatRestore

            #Run log now
            $splatBackupDiff = @{
                SqlInstance     = $TestConfig.InstanceCopy1
                Database        = $backuprestoredb
                BackupDirectory = $NetworkPath
                Type            = "Log"
            }
            $diffBackupResults = Backup-DbaDatabase @splatBackupDiff
            $backupPaths += $diffBackupResults.FullName
        }

        AfterAll {
            $backupPaths | Select-Object -Unique | Remove-Item -ErrorAction SilentlyContinue
        }

        It "continues the restore over existing database using backup history" {
            # It should already have a backup history (full+diff) by this time
            $splatCopyContinue = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                Database      = $backuprestoredb
                BackupRestore = $true
                UseLastBackup = $true
                Continue      = $true
            }
            $results = Copy-DbaDatabase @splatCopyContinue
            $results.Name | Should -Be $backuprestoredb
            $results.Status | Should -Be "Successful"
        }

        It "retains its name, recovery model, and status." {
            $splatGetDbs = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
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
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -ExcludeSystem | Remove-DbaDatabase
        }

        AfterAll {
            $splatStopProcess = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -ExcludeSystem | Remove-DbaDatabase
        }

        It "Should have renamed a single db" {
            $newname = "copy$(Get-Random)"
            $splatCopyRename = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                Database      = $backuprestoredb
                BackupRestore = $true
                SharedPath    = $NetworkPath
                NewName       = $newname
            }
            $results = Copy-DbaDatabase @splatCopyRename
            $results[0].DestinationDatabase | Should -Be $newname
            $files = Get-DbaDbFile -Sqlinstance $TestConfig.InstanceCopy2 -Database $newname
            ($files.PhysicalName -like "*$newname*").Count | Should -Be $files.Count
        }

        It "Should warn if trying to rename and prefix" {
            $splatCopyRenamePrefix = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
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
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                Database        = $backuprestoredb
                BackupRestore   = $true
                SharedPath      = $NetworkPath
                Prefix          = $prefix
                WarningVariable = "warn"
            }
            $results = Copy-DbaDatabase @splatCopyPrefix
            # $warn | Should -BeNullOrEmpty
            $results[0].DestinationDatabase | Should -Be "$prefix$backuprestoredb"
            $files = Get-DbaDbFile -Sqlinstance $TestConfig.InstanceCopy2 -Database "$prefix$backuprestoredb"
            ($files.PhysicalName -like "*$prefix$backuprestoredb*").Count | Should -Be $files.Count
        }
    }

    Context "Copying with renames using detachattach" {
        BeforeAll {
            $splatStopProcess = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue

            $splatRemoveDb = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = $backuprestoredb
            }
            Remove-DbaDatabase @splatRemoveDb
        }

        It "Should have renamed a single db" {
            $newname = "copy$(Get-Random)"
            $splatDetachRename = @{
                Source       = $TestConfig.InstanceCopy1
                Destination  = $TestConfig.InstanceCopy2
                Database     = $backuprestoredb
                DetachAttach = $true
                NewName      = $newname
                Reattach     = $true
            }
            $results = Copy-DbaDatabase @splatDetachRename
            $results[0].DestinationDatabase | Should -Be $newname
            $files = Get-DbaDbFile -Sqlinstance $TestConfig.InstanceCopy2 -Database $newname
            ($files.PhysicalName -like "*$newname*").Count | Should -Be $files.Count
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $newname
        }

        It "Should prefix databasename and files" {
            $prefix = "copy$(Get-Random)"
            $splatDetachPrefix = @{
                Source       = $TestConfig.InstanceCopy1
                Destination  = $TestConfig.InstanceCopy2
                Database     = $backuprestoredb
                DetachAttach = $true
                Reattach     = $true
                Prefix       = $prefix
            }
            $results = Copy-DbaDatabase @splatDetachPrefix
            $results[0].DestinationDatabase | Should -Be "$prefix$backuprestoredb"
            $files = Get-DbaDbFile -Sqlinstance $TestConfig.InstanceCopy2 -Database "$prefix$backuprestoredb"
            ($files.PhysicalName -like "*$prefix$backuprestoredb*").Count | Should -Be $files.Count
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database "$prefix$backuprestoredb"
        }

        It "Should warn and exit if newname and >1 db specified" {
            $splatRestore = @{
                SqlInstance                      = $TestConfig.InstanceCopy1
                Path                             = "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016"
                UseDestinationDefaultDirectories = $true
            }
            $null = Restore-DbaDatabase @splatRestore

            $splatDetachMultiple = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                Database        = $backuprestoredb, "RestoreTimeClean"
                DetachAttach    = $true
                Reattach        = $true
                NewName         = "warn"
                WarningVariable = "warnvar"
            }
            $null = Copy-DbaDatabase @splatDetachMultiple 3> $null
            $warnvar | Should -BeLike "*Cannot use NewName when copying multiple databases"
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database "RestoreTimeClean"
        }
    }

    Context "SetSourceOffline regression test for issue #9546" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatStopProcess = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue

            $random = Get-Random
            $offlineTestDb = "dbatoolsci_offline_test$random"

            $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $server2.Query("CREATE DATABASE $offlineTestDb; ALTER DATABASE $offlineTestDb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")

            $server3 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $server3.Query("CREATE DATABASE $offlineTestDb; ALTER DATABASE $offlineTestDb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatRemoveDbs = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Database    = $offlineTestDb
            }
            Remove-DbaDatabase @splatRemoveDbs -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should not set source database offline when copy operation fails" {
            $splatCopyOffline = @{
                Source           = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                Database         = $offlineTestDb
                BackupRestore    = $true
                UseLastBackup    = $true
                SetSourceOffline = $true
                WarningAction    = "SilentlyContinue"
            }
            $results = Copy-DbaDatabase @splatCopyOffline

            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "Already exists on destination"

            $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $offlineTestDb
            $sourceDb.Status | Should -Not -BeLike "*Offline*"
        }

        It "Should set source database offline when copy operation succeeds" {
            $splatRemoveDestDb = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = $offlineTestDb
            }
            Remove-DbaDatabase @splatRemoveDestDb

            $splatBackup = @{
                SqlInstance     = $TestConfig.InstanceCopy1
                Database        = $offlineTestDb
                BackupDirectory = $NetworkPath
            }
            $null = Backup-DbaDatabase @splatBackup

            $splatCopySuccess = @{
                Source           = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                Database         = $offlineTestDb
                BackupRestore    = $true
                UseLastBackup    = $true
                SetSourceOffline = $true
            }
            $results = Copy-DbaDatabase @splatCopySuccess

            $results[0].Status | Should -Be "Successful"

            $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $offlineTestDb
            $sourceDb.Status | Should -BeLike "*Offline*"

            # Set database online again to be able to remove the files on remove of database
            $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceCopy1 -Database $offlineTestDb -Online
        }
    }

    Context "Setup validation stops the run before any work is done" {
        It "warns and copies nothing when -BackupRestore has neither -SharedPath nor -UseLastBackup" {
            $splatNoPath = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                Database      = $backuprestoredb
                BackupRestore = $true
                WarningAction = "SilentlyContinue"
            }
            $resultsNoPath = Copy-DbaDatabase @splatNoPath -WarningVariable warnNoPath

            $resultsNoPath | Should -BeNullOrEmpty
            ($warnNoPath -join "`n") | Should -BeLike "*you must specify -SharedPath or -UseLastBackup*"
        }

        It "warns and copies nothing when -SharedPath is combined with -UseLastBackup" {
            $splatBothPaths = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                Database      = $backuprestoredb
                BackupRestore = $true
                SharedPath    = $NetworkPath
                UseLastBackup = $true
                WarningAction = "SilentlyContinue"
            }
            $resultsBothPaths = Copy-DbaDatabase @splatBothPaths -WarningVariable warnBothPaths

            $resultsBothPaths | Should -BeNullOrEmpty
            ($warnBothPaths -join "`n") | Should -BeLike "*-SharedPath cannot be used with -UseLastBackup*"
        }

        It "warns and copies nothing when -Continue is used without -UseLastBackup" {
            $splatContinueOnly = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                Database      = $backuprestoredb
                BackupRestore = $true
                SharedPath    = $NetworkPath
                Continue      = $true
                WarningAction = "SilentlyContinue"
            }
            $resultsContinueOnly = Copy-DbaDatabase @splatContinueOnly -WarningVariable warnContinueOnly

            $resultsContinueOnly | Should -BeNullOrEmpty
            ($warnContinueOnly -join "`n") | Should -BeLike "*-Continue cannot be used without -UseLastBackup*"
        }
    }

    Context "WhatIf leaves the destination untouched" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $whatIfDb = "dbatoolsci_whatif$(Get-Random)"

            $serverWhatIfSource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $serverWhatIfSource.Query("CREATE DATABASE $whatIfDb; ALTER DATABASE $whatIfDb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatRemoveWhatIf = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Database    = $whatIfDb
            }
            Remove-DbaDatabase @splatRemoveWhatIf -ErrorAction SilentlyContinue

            Get-ChildItem -Path $NetworkPath -Filter "*$whatIfDb*" -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "emits no migration result and does not create the database on the destination" {
            $splatWhatIf = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                Database      = $whatIfDb
                BackupRestore = $true
                SharedPath    = $NetworkPath
                WhatIf        = $true
            }
            $resultsWhatIf = Copy-DbaDatabase @splatWhatIf

            $resultsWhatIf | Should -BeNullOrEmpty

            $destWhatIfDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $whatIfDb
            $destWhatIfDb | Should -BeNullOrEmpty
        }
    }

    Context "State carries across piped records" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $carryDb = "dbatoolsci_carry$(Get-Random)"

            $serverCarrySource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $serverCarrySource.Query("CREATE DATABASE $carryDb; ALTER DATABASE $carryDb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatRemoveCarry = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Database    = $carryDb
            }
            Remove-DbaDatabase @splatRemoveCarry -ErrorAction SilentlyContinue

            Get-ChildItem -Path $NetworkPath -Filter "*$carryDb*" -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "reuses the earlier record's backup and reports the elapsed summary" {
            $carrySourceDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $carryDb

            # -Source is required even though the databases arrive on the pipeline: the setup guard
            # runs before any pipeline object is bound, so it always sees an empty -InputObject and
            # refuses without it. -NoBackupCleanup keeps the first record's backup on disk, which is
            # what the second record has to find for the reuse to be observable at all.
            $splatCarry = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                BackupRestore   = $true
                SharedPath      = $NetworkPath
                NumberFiles     = 1
                Force           = $true
                NoBackupCleanup = $true
            }
            $carryOutput = $carrySourceDb, $carrySourceDb | Copy-DbaDatabase @splatCarry -Verbose 4>&1

            $carryVerbose = ($carryOutput | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message }) -join "`n"
            $carryResults = @($carryOutput | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })

            $carryResults.Count | Should -Be 2
            $carryResults[0].Status | Should -Be "Successful"
            $carryResults[1].Status | Should -Be "Successful"

            # The backup taken for the first record is remembered, so the second record restores from it
            # instead of taking a second backup. One file means the collection survived the record boundary.
            $carryBackups = @(Get-ChildItem -Path $NetworkPath -Filter "*$carryDb*" -ErrorAction SilentlyContinue)
            $carryBackups.Count | Should -Be 1

            # The summary is only written when the stopwatch started during a record is still readable
            # afterwards; without it the command reports that no work was done.
            $carryVerbose | Should -BeLike "*Database migration finished*"
            $carryVerbose | Should -Not -BeLike "*No work was done*"
        }
    }

    Context "When resolving the command name in a cold shell" {
        BeforeAll {
            # Every other leg runs in a session that imported dbatools long before Pester started,
            # so none of them can tell the binary cmdlet apart from the retired script function -
            # whichever got there first answers to the name. This leg starts a shell of the same
            # edition that has imported nothing, loads the module the way a consumer does, and asks
            # what the name resolves to. dbatools.psm1 is the import under test on purpose: it is
            # the loader that pulls the satellite in by path, and importing the manifest by name
            # cannot work in a dev tree because the satellites are not on PSModulePath.
            $moduleBase = @(Get-Module -Name dbatools)[0].ModuleBase
            $shellPath = (Get-Process -Id $PID).Path
            $probePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-resolve-$(Get-Random).ps1"

            # Get-Command -All so a retired function shadowing the cmdlet shows up as a second
            # entry rather than silently winning; the count is what proves it is not there.
            $probeBody = @"
Import-Module -Name "$moduleBase\dbatools.psm1" -DisableNameChecking
`$resolved = Get-Command -Name Copy-DbaDatabase -ErrorAction SilentlyContinue
`$allResolved = @(Get-Command -Name Copy-DbaDatabase -All -ErrorAction SilentlyContinue)
`$functionCount = @(`$allResolved | Where-Object { `$PSItem.CommandType -eq "Function" }).Count
`$satelliteLoaded = [bool](Get-Module -Name dbatools.migration)
"RESOLVED|`$(`$resolved.CommandType)|`$(`$resolved.ModuleName)|`$functionCount|`$satelliteLoaded"
"@
            Set-Content -Path $probePath -Value $probeBody -Encoding UTF8

            $probeOutput = & $shellPath -NoProfile -NonInteractive -File $probePath 2>&1
            $probeFields = @("$(@($probeOutput | Where-Object { "$PSItem" -like "RESOLVED|*" })[0])" -split "\|")
        }

        AfterAll {
            Remove-Item -Path $probePath -ErrorAction SilentlyContinue
        }

        It "Should resolve to the binary cmdlet shipped by dbatools.migration" {
            $probeFields[1] | Should -Be "Cmdlet"
            $probeFields[2] | Should -Be "dbatools.migration"
        }

        It "Should load the satellite and leave no retired function shadowing the name" {
            $probeFields[4] | Should -Be "True"
            $probeFields[3] | Should -Be "0"
        }
    }
    # The two Azure storage legs that lived here needed $env:azurepasswd and a reachable storage
    # account, neither of which this lab has, so they could only ever be declared and never run.
    # They are preserved verbatim, with the setup they need, on potatoqualitee/migration.
}
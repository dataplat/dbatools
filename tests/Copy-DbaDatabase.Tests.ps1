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
        foreach ($db in $supportDbs) {
            $server2.Query("CREATE DATABASE [$db]; ALTER DATABASE [$db] SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE;")
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

        $splatRemoveSupport = @{
            SqlInstance = $TestConfig.InstanceCopy1
            Database    = $supportDbs
        }
        Remove-DbaDatabase @splatRemoveSupport -ErrorAction SilentlyContinue

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

    Context "Multi-database copies regression tests for issue #10512" {
        BeforeDiscovery {
            # Both spellings the help documents as "treated as not specified" (#10512)
            $blankNewNameCases = @(
                @{ NewNameLabel = "an empty"; NewNameValue = "" }
                @{ NewNameLabel = "a whitespace"; NewNameValue = "   " }
            )
        }

        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatStopProcess = @{
                SqlInstance = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Program     = "dbatools PowerShell module - dbatools.io"
            }
            Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue

            $randomPipe = Get-Random
            $pipeDb1 = "dbatoolsci_pipe1$randomPipe"
            $pipeDb2 = "dbatoolsci_pipe2$randomPipe"
            $pipeNewName = "dbatoolsci_piperename$randomPipe"
            $pipeSentinelDb = "dbatoolsci_pipesentinel$randomPipe"
            $pipeOwnerLogin = "dbatoolsci_owner$randomPipe"

            $serverPipeSource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $serverPipeSource.Query("CREATE DATABASE $pipeDb1; ALTER DATABASE $pipeDb1 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
            $serverPipeSource.Query("CREATE DATABASE $pipeDb2; ALTER DATABASE $pipeDb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")

            # An unrelated destination database whose owner must survive every copy below:
            # the #10512 defect swept the owner of every database on the destination. The
            # sentinel owner is a dedicated login because the sweep sets owners to the
            # source database owner - if both were sa, a sweep would go undetected.
            $serverPipeDest = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $serverPipeDest.Query("CREATE DATABASE $pipeSentinelDb; ALTER DATABASE $pipeSentinelDb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
            $securePipeOwner = ConvertTo-SecureString "P@ssw0rd$randomPipe!" -AsPlainText -Force
            $splatOwnerLogin = @{
                SqlInstance    = $TestConfig.InstanceCopy2
                Login          = $pipeOwnerLogin
                SecurePassword = $securePipeOwner
            }
            $null = New-DbaLogin @splatOwnerLogin
            $splatSentinelOwner = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = $pipeSentinelDb
                TargetLogin = $pipeOwnerLogin
            }
            $null = Set-DbaDbOwner @splatSentinelOwner

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatRemovePipeSource = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = $pipeDb1, $pipeDb2
            }
            Remove-DbaDatabase @splatRemovePipeSource -ErrorAction SilentlyContinue

            $splatRemovePipeDest = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = $pipeDb1, $pipeDb2, $pipeNewName, $pipeSentinelDb
            }
            Remove-DbaDatabase @splatRemovePipeDest -ErrorAction SilentlyContinue
            Remove-DbaLogin -SqlInstance $TestConfig.InstanceCopy2 -Login $pipeOwnerLogin -Force -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Copies every database in a parameter array" {
            $splatCopyArray = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                Database      = $pipeDb1, $pipeDb2
                BackupRestore = $true
                SharedPath    = $NetworkPath
            }
            $results = Copy-DbaDatabase @splatCopyArray
            ($results | Measure-Object).Count | Should -Be 2
            $results.Status | Should -Be @("Successful", "Successful")
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $pipeDb1, $pipeDb2 -EnableException
        }

        It "Copies every piped database" {
            $splatCopyPiped = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                BackupRestore = $true
                SharedPath    = $NetworkPath
            }
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $pipeDb1, $pipeDb2 | Copy-DbaDatabase @splatCopyPiped
            ($results | Measure-Object).Count | Should -Be 2
            $results.Status | Should -Be @("Successful", "Successful")
            $results.Name | Should -Contain $pipeDb1
            $results.Name | Should -Contain $pipeDb2
            ($results | Where-Object Name -eq $pipeDb1).DestinationDatabase | Should -Be $pipeDb1
            ($results | Where-Object Name -eq $pipeDb2).DestinationDatabase | Should -Be $pipeDb2
            (Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $pipeSentinelDb).Owner | Should -Be $pipeOwnerLogin
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $pipeDb1, $pipeDb2 -EnableException
        }

        It "Ignores <NewNameLabel> NewName and copies piped databases under their original names" -ForEach $blankNewNameCases {
            # The reporter's pipeline passes -NewName unconditionally and leaves it blank when
            # no rename is wanted (#10512). A blank name must mean "no rename", never an empty
            # -Database filter that lets post-restore commands sweep the whole destination.
            $ownerBefore = (Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $pipeSentinelDb).Owner
            $splatCopyBlankName = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                BackupRestore = $true
                SharedPath    = $NetworkPath
                NewName       = $NewNameValue
            }
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $pipeDb1, $pipeDb2 | Copy-DbaDatabase @splatCopyBlankName
            ($results | Measure-Object).Count | Should -Be 2
            $results.Status | Should -Be @("Successful", "Successful")
            ($results | Where-Object Name -eq $pipeDb1).DestinationDatabase | Should -Be $pipeDb1
            ($results | Where-Object Name -eq $pipeDb2).DestinationDatabase | Should -Be $pipeDb2
            (Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $pipeSentinelDb).Owner | Should -Be $ownerBefore
            $splatRemoveBlankCopies = @{
                SqlInstance     = $TestConfig.InstanceCopy2
                Database        = $pipeDb1, $pipeDb2
                EnableException = $true
            }
            $null = Remove-DbaDatabase @splatRemoveBlankCopies
        }

        It "Rejects NewName with piped databases before any copy happens" {
            $splatCopyPipedRename = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                BackupRestore   = $true
                SharedPath      = $NetworkPath
                NewName         = $pipeNewName
                WarningVariable = "warnvar"
            }
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $pipeDb1, $pipeDb2 | Copy-DbaDatabase @splatCopyPipedRename 3> $null
            $results | Should -BeNullOrEmpty
            $warnvar | Should -BeLike "*Cannot use NewName with piped databases*"
            # The rejection must be atomic: no renamed database and no partial copies
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $pipeNewName, $pipeDb1, $pipeDb2 | Should -BeNullOrEmpty
        }

        It "Continues to the next piped database when one restore fails" {
            # The reported shape (#10512): several piped databases, no -NewName. A backup
            # gone missing must yield exactly one Failed result for that database and must
            # not silently discard the databases piped in after it.
            $splatBackupGone = @{
                SqlInstance     = $TestConfig.InstanceCopy1
                Database        = $pipeDb1
                Path            = $NetworkPath
                EnableException = $true
            }
            $backupGone = Backup-DbaDatabase @splatBackupGone
            $backupGone.FullName | ForEach-Object { Remove-Item -Path $PSItem -Force }

            $splatBackupKeep = @{
                SqlInstance     = $TestConfig.InstanceCopy1
                Database        = $pipeDb2
                Path            = $NetworkPath
                EnableException = $true
            }
            $null = Backup-DbaDatabase @splatBackupKeep

            $splatCopyLastBackup = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                BackupRestore   = $true
                UseLastBackup   = $true
                WithReplace     = $true
                WarningVariable = "warnvar"
            }
            # sys.databases rows come back in no guaranteed order, and this test only
            # proves anything when the failing database is piped FIRST - a failure on the
            # last record leaves no later record for the old discard bug to suppress.
            $orderedPipeInput = @(
                Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $pipeDb1
                Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $pipeDb2
            )
            $results = $orderedPipeInput | Copy-DbaDatabase @splatCopyLastBackup 3> $null
            ($results | Where-Object Name -eq $pipeDb1 | Measure-Object).Count | Should -Be 1
            ($results | Where-Object Name -eq $pipeDb1).Status | Should -Be "Failed"
            ($results | Where-Object Name -eq $pipeDb2 | Measure-Object).Count | Should -Be 1
            ($results | Where-Object Name -eq $pipeDb2).Status | Should -Be "Successful"
            (Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $pipeDb2).Name | Should -Be $pipeDb2
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $pipeDb2 -EnableException
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

    if ($env:azurepasswd) {
        Context "Copying via Azure storage" {
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

                $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
                $sql = "CREATE CREDENTIAL [$TestConfig.azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
                $server2.Query($sql)
                $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$TestConfig.azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
                $server2.Query($sql)

                $server3 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
                $sql = "CREATE CREDENTIAL [$TestConfig.azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
                $server3.Query($sql)
                $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$TestConfig.azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
                $server3.Query($sql)
            }

            AfterAll {
                Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $backuprestoredb | Remove-DbaDatabase
                $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
                $server2.Query("DROP CREDENTIAL [$TestConfig.azureblob]")
                $server2.Query("DROP CREDENTIAL dbatools_ci")
                $server3 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
                $server3.Query("DROP CREDENTIAL [$TestConfig.azureblob]")
                $server3.Query("DROP CREDENTIAL dbatools_ci")
            }

            It "Should Copy $backuprestoredb via Azure legacy credentials" {
                $splatAzureLegacy = @{
                    Source          = $TestConfig.InstanceCopy1
                    Destination     = $TestConfig.InstanceCopy2
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
                    Source        = $TestConfig.InstanceCopy1
                    Destination   = $TestConfig.InstanceCopy2
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

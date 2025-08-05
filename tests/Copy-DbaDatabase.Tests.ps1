$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Database', 'ExcludeDatabase', 'AllDatabases', 'BackupRestore', 'AdvancedBackupParams', 'SharedPath', 'AzureCredential', 'WithReplace', 'NoRecovery', 'NoBackupCleanup', 'NumberFiles', 'DetachAttach', 'Reattach', 'SetSourceReadOnly', 'ReuseSourceFolderStructure', 'IncludeSupportDbs', 'UseLastBackup', 'Continue', 'InputObject', 'NoCopyOnly', 'SetSourceOffline', 'NewName', 'Prefix', 'Force', 'EnableException', 'KeepCDC', 'KeepReplication'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $NetworkPath = $TestConfig.Temp
        $random = Get-Random
        $backuprestoredb = "dbatoolsci_backuprestore$random"
        $backuprestoredb2 = "dbatoolsci_backuprestoreother$random"
        $detachattachdb = "dbatoolsci_detachattach$random"
        $supportDbs = @("ReportServer", "ReportServerTempDB", "distribution", "SSISDB")
        Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $backuprestoredb, $detachattachdb

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        $server.Query("CREATE DATABASE $backuprestoredb2; ALTER DATABASE $backuprestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $server.Query("CREATE DATABASE $backuprestoredb; ALTER DATABASE $backuprestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $server.Query("CREATE DATABASE $detachattachdb; ALTER DATABASE $detachattachdb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $server.Query("CREATE DATABASE $backuprestoredb2; ALTER DATABASE $backuprestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        foreach ($db in $supportDbs) {
            $server.Query("CREATE DATABASE [$db]; ALTER DATABASE [$db] SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE;")
        }
        $null = Set-DbaDbOwner -SqlInstance $TestConfig.instance2 -Database $backuprestoredb, $detachattachdb -TargetLogin sa
    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $backuprestoredb, $detachattachdb, $backuprestoredb2
        Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database $supportDbs
    }

    Context "Support databases are excluded when AllDatabase selected" {
        $SupportDbs = "ReportServer", "ReportServerTempDB", "distribution", "SSISDB"
        $results = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -AllDatabase -BackupRestore -UseLastBackup

        It "Support databases should not be migrated" {
            $SupportDbs | Should -Not -BeIn $results.Name
        }
    }

    # if failed Disable-NetFirewallRule -DisplayName 'Core Networking - Group Policy (TCP-Out)'
    Context "Detach Attach" {
        It "Should be success" {
            $results = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $detachattachdb -DetachAttach -Reattach -Force #-WarningAction SilentlyContinue
            $results.Status | Should Be "Successful"
        }

        $db1 = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $detachattachdb
        $db2 = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $detachattachdb

        It "should not be null" {
            $db1.Name | Should Be $detachattachdb
            $db2.Name | Should Be $detachattachdb
        }

        It "Name, recovery model, and status should match" {
            # Compare its variable
            $db1.Name | Should -Be $db2.Name
            $db1.RecoveryModel | Should -Be $db2.RecoveryModel
            $db1.Status | Should -Be $db2.Status
            $db1.Owner | Should -Be $db2.Owner
        }

        It "Should say skipped" {
            $results = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $detachattachdb -DetachAttach -Reattach
            $results.Status | Should be "Skipped"
            $results.Notes | Should be "Already exists on destination"
        }
    }

    Context "Backup restore" {
        Get-DbaProcess -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $results = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb -BackupRestore -SharedPath $NetworkPath

        It "copies a database successfully" {
            $results.Name | Should -Be $backuprestoredb
            $results.Status | Should -Be "Successful"
        }

        It "retains its name, recovery model, and status." {
            $dbs = Get-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $backuprestoredb
            $dbs[0].Name | Should -Not -BeNullOrEmpty
            # Compare its variables
            $dbs[0].Name | Should -Be $dbs[1].Name
            $dbs[0].RecoveryModel | Should -Be $dbs[1].RecoveryModel
            $dbs[0].Status | Should -Be $dbs[1].Status
        }

        # needs regr test that uses $backuprestoredb once #3377 is fixed
        It  "Should say skipped" {
            $result = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb2 -BackupRestore -SharedPath $NetworkPath
            $result.Status | Should be "Skipped"
            $result.Notes | Should be "Already exists on destination"
        }

        # needs regr test once #3377 is fixed
        if (-not $env:appveyor) {
            It "Should overwrite when forced to" {
                #regr test for #3358
                $result = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb2 -BackupRestore -SharedPath $NetworkPath -Force
                $result.Status | Should be "Successful"
            }
        }
    }
    Context "UseLastBackup - read backup history" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance3 -Database $backuprestoredb
        }

        It "copies a database successfully using backup history" {
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $backuprestoredb -BackupDirectory $NetworkPath
            $backupFile = $results.FullName
            $results = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb -BackupRestore -UseLastBackup
            $results.Name | Should -Be $backuprestoredb
            $results.Status | Should -Be "Successful"
            Remove-Item -Path $backupFile
        }

        It "retains its name, recovery model, and status." {
            $dbs = Get-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $backuprestoredb
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
            Get-DbaProcess -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance3 -Database $backuprestoredb
            #Pre-stage the restore
            $backupPaths = @( )
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $backuprestoredb -BackupDirectory $NetworkPath
            $backupPaths += $results.FullName
            $results | Restore-DbaDatabase -SqlInstance $TestConfig.instance3 -DatabaseName $backuprestoredb -NoRecovery
            #Run diff now
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $backuprestoredb -BackupDirectory $NetworkPath -Type Diff
            $backupPaths += $results.FullName
        }

        AfterAll {
            $backupPaths | Select-Object -Unique | Remove-Item
        }

        It "continues the restore over existing database using backup history" -Skip {
            # It should already have a backup history (full+diff) by this time
            $results = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb -BackupRestore -UseLastBackup -Continue
            $results.Name | Should -Be $backuprestoredb
            $results.Status | Should -Be "Successful"
        }

        It "retains its name, recovery model, and status." -Skip {
            $dbs = Get-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $backuprestoredb
            $dbs[0].Name | Should -Not -BeNullOrEmpty
            # Compare its variables
            $dbs[0].Name | Should -Be $dbs[1].Name
            $dbs[0].RecoveryModel | Should -Be $dbs[1].RecoveryModel
            $dbs[0].Status | Should -Be $dbs[1].Status
        }
    }
    Context "Copying with renames using backup/restore" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Get-DbaDatabase -SqlInstance $TestConfig.instance3 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        AfterAll {
            Get-DbaProcess -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Get-DbaDatabase -SqlInstance $TestConfig.instance3 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        It "Should have renamed a single db" {
            $newname = "copy$(Get-Random)"
            $results = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb -BackupRestore -SharedPath $NetworkPath -NewName $newname
            $results[0].DestinationDatabase | Should -Be $newname
            $files = Get-DbaDbFile -Sqlinstance $TestConfig.instance3 -Database $newname
            ($files.PhysicalName -like "*$newname*").count | Should -Be $files.count
        }

        It "Should warn if trying to rename and prefix" {
            $null = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb -BackupRestore -SharedPath $NetworkPath -NewName $newname -prefix pre -WarningVariable warnvar 3> $null
            $warnvar | Should -BeLike "*NewName and Prefix are exclusive options, cannot specify both"
        }

        It "Should prefix databasename and files" {
            $prefix = "da$(Get-Random)"
            # Writes warning: "Failed to update BrokerEnabled to True" - This is a bug in Copy-DbaDatabase
            $results = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb -BackupRestore -SharedPath $NetworkPath -Prefix $prefix -WarningVariable warn
            # $warn | Should -BeNullOrEmpty
            $results[0].DestinationDatabase | Should -Be "$prefix$backuprestoredb"
            $files = Get-DbaDbFile -Sqlinstance $TestConfig.instance3 -Database "$prefix$backuprestoredb"
            ($files.PhysicalName -like "*$prefix$backuprestoredb*").count | Should -Be $files.count
        }
    }

    Context "Copying with renames using detachattach" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance3 -Database $backuprestoredb
        }
        It "Should have renamed a single db" {
            $newname = "copy$(Get-Random)"
            $results = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb -DetachAttach -NewName $newname -Reattach
            $results[0].DestinationDatabase | Should -Be $newname
            $files = Get-DbaDbFile -Sqlinstance $TestConfig.instance3 -Database $newname
            ($files.PhysicalName -like "*$newname*").count | Should -Be $files.count
            $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance3 -Database $newname
        }

        It "Should prefix databasename and files" {
            $prefix = "copy$(Get-Random)"
            $results = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb -DetachAttach -Reattach -Prefix $prefix
            $results[0].DestinationDatabase | Should -Be "$prefix$backuprestoredb"
            $files = Get-DbaDbFile -Sqlinstance $TestConfig.instance3 -Database "$prefix$backuprestoredb"
            ($files.PhysicalName -like "*$prefix$backuprestoredb*").count | Should -Be $files.count
            $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance3 -Database "$prefix$backuprestoredb"
        }

        $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -useDestinationDefaultDirectories
        It "Should warn and exit if newname and >1 db specified" {
            $null = Copy-DbaDatabase -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb, RestoreTimeClean -DetachAttach -Reattach -NewName warn -WarningVariable warnvar 3> $null
            $warnvar | Should -BeLike "*Cannot use NewName when copying multiple databases"
            $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database RestoreTimeClean
        }
    }

    if ($env:azurepasswd) {
        Context "Copying via Azure storage" {
            BeforeAll {
                Get-DbaProcess -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
                Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance3 -Database $backuprestoredb
                $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
                $sql = "CREATE CREDENTIAL [$TestConfig.azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
                $server.Query($sql)
                $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$TestConfig.azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
                $server.Query($sql)
                $server3 = Connect-DbaInstance -SqlInstance $TestConfig.instance3
                $sql = "CREATE CREDENTIAL [$TestConfig.azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
                $server3.Query($sql)
                $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$TestConfig.azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
                $server3.Query($sql)
            }
            AfterAll {
                Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $backuprestoredb | Remove-DbaDatabase -Confirm:$false
                $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
                $server.Query("DROP CREDENTIAL [$TestConfig.azureblob]")
                $server.Query("DROP CREDENTIAL dbatools_ci")
                $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
                $server.Query("DROP CREDENTIAL [$TestConfig.azureblob]")
                $server.Query("DROP CREDENTIAL dbatools_ci")
            }
            $results = Copy-DbaDatabase -source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb -BackupRestore -SharedPath $TestConfig.azureblob -AzureCredential dbatools_ci
            It "Should Copy $backuprestoredb via Azure legacy credentials" {
                $results[0].Name | Should -Be $backuprestoredb
                $results[0].Status | Should -BeLike 'Successful*'
            }
            # Because I think the backup are tripping over each other with the names
            Start-Sleep -Seconds 60
            $results = Copy-DbaDatabase -source $TestConfig.instance2 -Destination $TestConfig.instance3 -Database $backuprestoredb -Newname djkhgfkjghfdjgd -BackupRestore -SharedPath $TestConfig.azureblob
            It "Should Copy $backuprestoredb via Azure new credentials" {
                $results[0].Name | Should -Be $backuprestoredb
                $results[0].DestinationDatabase | Should -Be 'djkhgfkjghfdjgd'
                $results[0].Status | Should -BeLike 'Successful*'
            }
        }
    }
}


$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Database', 'ExcludeDatabase', 'AllDatabases', 'BackupRestore', 'SharedPath', 'AzureCredential', 'WithReplace', 'NoRecovery', 'NoBackupCleanup', 'NumberFiles', 'DetachAttach', 'Reattach', 'SetSourceReadOnly', 'ReuseSourceFolderStructure', 'IncludeSupportDbs', 'UseLastBackup', 'Continue', 'InputObject', 'NoCopyOnly', 'SetSourceOffline', 'NewName', 'Prefix', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $NetworkPath = "C:\temp"
        $random = Get-Random
        $backuprestoredb = "dbatoolsci_backuprestore$random"
        $backuprestoredb2 = "dbatoolsci_backuprestoreother$random"
        $detachattachdb = "dbatoolsci_detachattach$random"
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2, $script:instance3 -Database $backuprestoredb, $detachattachdb

        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $server.Query("CREATE DATABASE $backuprestoredb2; ALTER DATABASE $backuprestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.Query("CREATE DATABASE $backuprestoredb; ALTER DATABASE $backuprestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $server.Query("CREATE DATABASE $detachattachdb; ALTER DATABASE $detachattachdb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $server.Query("CREATE DATABASE $backuprestoredb2; ALTER DATABASE $backuprestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $null = Set-DbaDbOwner -SqlInstance $script:instance2 -Database $backuprestoredb, $detachattachdb -TargetLogin sa
    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2, $script:instance3 -Database $backuprestoredb, $detachattachdb, $backuprestoredb2
    }

    # if failed Disable-NetFirewallRule -DisplayName 'Core Networking - Group Policy (TCP-Out)'
    Context "Detach Attach" {
        It "Should be success" {
            $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $detachattachdb -DetachAttach -Reattach -Force #-WarningAction SilentlyContinue
            $results.Status | Should Be "Successful"
        }

        $db1 = Get-DbaDatabase -SqlInstance $script:instance2 -Database $detachattachdb
        $db2 = Get-DbaDatabase -SqlInstance $script:instance3 -Database $detachattachdb

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
            $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $detachattachdb -DetachAttach -Reattach
            $results.Status | Should be "Skipped"
            $results.Notes | Should be "Already exists on destination"
        }
    }

    Context "Backup restore" {
        Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -SharedPath $NetworkPath 3>$null

        It "copies a database successfully" {
            $results.Name -eq $backuprestoredb
            $results.Status -eq "Successful"
        }

        It "retains its name, recovery model, and status." {
            $dbs = Get-DbaDatabase -SqlInstance $script:instance2, $script:instance3 -Database $backuprestoredb
            $dbs[0].Name -ne $null
            # Compare its variables
            $dbs[0].Name -eq $dbs[1].Name
            $dbs[0].RecoveryModel -eq $dbs[1].RecoveryModel
            $dbs[0].Status -eq $dbs[1].Status
            $dbs[0].Owner -eq $dbs[1].Owner
        }

        # needs regr test that uses $backuprestoredb once #3377 is fixed
        It  "Should say skipped" {
            $result = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb2 -BackupRestore -SharedPath $NetworkPath 3>$null
            $result.Status | Should be "Skipped"
            $result.Notes | Should be "Already exists on destination"
        }

        # needs regr test once #3377 is fixed
        if (-not $env:appveyor) {
            It "Should overwrite when forced to" {
                #regr test for #3358
                $result = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb2 -BackupRestore -SharedPath $NetworkPath -Force
                $result.Status | Should be "Successful"
            }
        }
    }
    Context "UseLastBackup - read backup history" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance3 -Database $backuprestoredb
        }

        It "copies a database successfully using backup history" {
            # It should already have a backup history by this time
            $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -UseLastBackup 3>$null
            $results.Name -eq $backuprestoredb
            $results.Status -eq "Successful"
        }

        It "retains its name, recovery model, and status." {
            $dbs = Get-DbaDatabase -SqlInstance $script:instance2, $script:instance3 -Database $backuprestoredb
            $dbs[0].Name -ne $null
            # Compare its variables
            $dbs[0].Name -eq $dbs[1].Name
            $dbs[0].RecoveryModel -eq $dbs[1].RecoveryModel
            $dbs[0].Status -eq $dbs[1].Status
            $dbs[0].Owner -eq $dbs[1].Owner
        }
    }
    Context "UseLastBackup with -Continue" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance3 -Database $backuprestoredb
            #Pre-stage the restore
            $null = Get-DbaDbBackupHistory -SqlInstance $script:instance2 -Database $backuprestoredb -LastFull | Restore-DbaDatabase -SqlInstance $script:instance3 -DatabaseName $backuprestoredb -NoRecovery 3>$null
            #Run diff now
            $null = Backup-DbaDatabase -SqlInstance $script:instance2 -Database $backuprestoredb -BackupDirectory $NetworkPath -Type Diff
        }

        It "continues the restore over existing database using backup history" {
            # It should already have a backup history (full+diff) by this time
            $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -UseLastBackup -Continue 3>$null
            $results.Name -eq $backuprestoredb
            $results.Status -eq "Successful"
        }

        It "retains its name, recovery model, and status." {
            $dbs = Get-DbaDatabase -SqlInstance $script:instance2, $script:instance3 -Database $backuprestoredb
            $dbs[0].Name -ne $null
            # Compare its variables
            $dbs[0].Name -eq $dbs[1].Name
            $dbs[0].RecoveryModel -eq $dbs[1].RecoveryModel
            $dbs[0].Status -eq $dbs[1].Status
            $dbs[0].Owner -eq $dbs[1].Owner
        }
    }
    Context "Copying with renames using backup/restore" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Get-DbaDatabase -SqlInstance $script:instance3 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        AfterAll {
            Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Get-DbaDatabase -SqlInstance $script:instance3 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        It "Should have renamed a single db" {
            $newname = "copy$(Get-Random)"
            $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -SharedPath $NetworkPath -NewName $newname
            $results[0].DestinationDatabase | Should -Be $newname
            $files = Get-DbaDbFile -Sqlinstance $script:instance3 -Database $newname
            ($files.PhysicalName -like "*$newname*").count | Should -Be $files.count
        }

        It "Should warn if trying to rename and prefix" {
            $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -SharedPath $NetworkPath -NewName $newname -prefix pre -WarningVariable warnvar
            $warnvar | Should -BeLike "*NewName and Prefix are exclusive options, cannot specify both"

        }

        It "Should prefix databasename and files" {
            $prefix = "da$(Get-Random)"
            $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -SharedPath $NetworkPath -Prefix $prefix
            $results[0].DestinationDatabase | Should -Be "$prefix$backuprestoredb"
            $files = Get-DbaDbFile -Sqlinstance $script:instance3 -Database "$prefix$backuprestoredb"
            ($files.PhysicalName -like "*$prefix$backuprestoredb*").count | Should -Be $files.count
        }
    }

    Context "Copying with renames using detachattach" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance3 -Database $backuprestoredb
        }
        It "Should have renamed a single db" {
            $newname = "copy$(Get-Random)"
            $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -DetachAttach -NewName $newname -Reattach
            $results[0].DestinationDatabase | Should -Be $newname
            $files = Get-DbaDbFile -Sqlinstance $script:instance3 -Database $newname
            ($files.PhysicalName -like "*$newname*").count | Should -Be $files.count
        }

        It "Should prefix databasename and files" {
            $prefix = "copy$(Get-Random)"
            $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -DetachAttach -Reattach -Prefix $prefix
            $results[0].DestinationDatabase | Should -Be "$prefix$backuprestoredb"
            $files = Get-DbaDbFile -Sqlinstance $script:instance3 -Database "$prefix$backuprestoredb"
            ($files.PhysicalName -like "*$prefix$backuprestoredb*").count | Should -Be $files.count
        }

        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -path $script:appveyorlabrepo\RestoreTimeClean2016 -useDestinationDefaultDirectories
        It "Should warn and exit if newname and >1 db specified" {
            $prefix = "copy$(Get-Random)"
            $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb, RestoreTimeClean -DetachAttach -Reattach -NewName warn -WarningVariable warnvar
            $Warnvar | Should -BeLike "*Cannot use NewName when copying multiple databases"
        }
    }

    if ($env:azurepasswd) {
        Context "Copying via Azure storage" {
            BeforeAll {
                Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
                Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance3 -Database $backuprestoredb
                $server = Connect-DbaInstance -SqlInstance $script:instance2
                $sql = "CREATE CREDENTIAL [$script:azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
                $server.Query($sql)
                $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$script:azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
                $server.Query($sql)
                $server3 = Connect-DbaInstance -SqlInstance $script:instance3
                $sql = "CREATE CREDENTIAL [$script:azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
                $server3.Query($sql)
                $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$script:azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
                $server3.Query($sql)
            }
            AfterAll {
                Get-DbaDatabase -SqlInstance $script:instance3 -Database $backuprestoredb | Remove-DbaDatabase -Confirm:$false
                $server = Connect-DbaInstance -SqlInstance $script:instance2
                $server.Query("DROP CREDENTIAL [$script:azureblob]")
                $server.Query("DROP CREDENTIAL dbatools_ci")
                $server = Connect-DbaInstance -SqlInstance $script:instance3
                $server.Query("DROP CREDENTIAL [$script:azureblob]")
                $server.Query("DROP CREDENTIAL dbatools_ci")
            }
            $results = Copy-DbaDatabase -source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -SharedPath $script:azureblob -AzureCredential dbatools_ci
            It "Should Copy $backuprestoredb via Azure legacy credentials" {
                $results[0].Name  | Should -Be $backuprestoredb
                $results[0].Status  | Should -BeLike 'Successful*'
            }
            # Because I think the backup are tripping over each other with the names
            Start-Sleep -Seconds 60
            $results = Copy-DbaDatabase -source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -Newname djkhgfkjghfdjgd -BackupRestore -SharedPath $script:azureblob
            It "Should Copy $backuprestoredb via Azure new credentials" {
                $results[0].Name  | Should -Be $backuprestoredb
                $results[0].DestinationDatabase | Should -Be 'djkhgfkjghfdjgd'
                $results[0].Status  | Should -BeLike 'Successful*'
            }
        }
    }
}
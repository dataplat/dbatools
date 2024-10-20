param($ModuleName = 'dbatools')

Describe "Copy-DbaDatabase" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $NetworkPath = "C:\temp"
        $random = Get-Random
        $backuprestoredb = "dbatoolsci_backuprestore$random"
        $backuprestoredb2 = "dbatoolsci_backuprestoreother$random"
        $detachattachdb = "dbatoolsci_detachattach$random"
        $supportDbs = @("ReportServer", "ReportServerTempDB", "distribution", "SSISDB")
        Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2, $global:instance3 -Database $backuprestoredb, $detachattachdb

        $server = Connect-DbaInstance -SqlInstance $global:instance3
        $server.Query("CREATE DATABASE $backuprestoredb2; ALTER DATABASE $backuprestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $server.Query("CREATE DATABASE $backuprestoredb; ALTER DATABASE $backuprestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $server.Query("CREATE DATABASE $detachattachdb; ALTER DATABASE $detachattachdb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $server.Query("CREATE DATABASE $backuprestoredb2; ALTER DATABASE $backuprestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        foreach ($db in $supportDbs) {
            $server.Query("CREATE DATABASE [$db]; ALTER DATABASE [$db] SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE;")
        }
        $null = Set-DbaDbOwner -SqlInstance $global:instance2 -Database $backuprestoredb, $detachattachdb -TargetLogin sa
    }

    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2, $global:instance3 -Database $backuprestoredb, $detachattachdb, $backuprestoredb2
        Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database $supportDbs
    }

    Context "Validate parameters" {
        BeforeDiscovery {
            [object[]]$params = (Get-Command Copy-DbaDatabase).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        }

        $requiredParameters = @(
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
        It "has all the required parameters" -ForEach $requiredParameters {
            (Get-Command Copy-DbaDatabase) | Should -HaveParameter $PSItem
        }

        $params = @(
            "Source",
            "SourceSqlCredential",
            "Destination",
            "DestinationSqlCredential"
        )
        It "has the required parameter: <_>" -ForEach $params {
            (Get-Command Copy-DbaDatabase) | Should -HaveParameter $PSItem
        }

        It "Source should be a Dataplat.Dbatools.Parameter.DbaInstanceParameter" {
            (Get-Command Copy-DbaDatabase).Parameters['Source'].ParameterType.FullName | Should -Be 'Dataplat.Dbatools.Parameter.DbaInstanceParameter'
        }

        It "SourceSqlCredential should be a System.Management.Automation.PSCredential" {
            (Get-Command Copy-DbaDatabase).Parameters['SourceSqlCredential'].ParameterType.FullName | Should -Be 'System.Management.Automation.PSCredential'
        }

        It "Destination should be a Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            (Get-Command Copy-DbaDatabase).Parameters['Destination'].ParameterType.FullName | Should -Be 'Dataplat.Dbatools.Parameter.DbaInstanceParameter[]'
        }

        It "DestinationSqlCredential should be a System.Management.Automation.PSCredential" {
            (Get-Command Copy-DbaDatabase).Parameters['DestinationSqlCredential'].ParameterType.FullName | Should -Be 'System.Management.Automation.PSCredential'
        }

        # Add similar tests for other parameters...
    }

    Context "Support databases are excluded when AllDatabase selected" {
        BeforeAll {
            $SupportDbs = "ReportServer", "ReportServerTempDB", "distribution", "SSISDB"
            $results = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -AllDatabase -BackupRestore -UseLastBackup
        }

        It "Support databases should not be migrated" {
            $SupportDbs | Should -Not -BeIn $results.Name
        }
    }

    Context "Detach Attach" {
        It "Should be success" {
            $results = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $detachattachdb -DetachAttach -Reattach -Force
            $results.Status | Should -Be "Successful"
        }

        It "should not be null" {
            $db1 = Get-DbaDatabase -SqlInstance $global:instance2 -Database $detachattachdb
            $db2 = Get-DbaDatabase -SqlInstance $global:instance3 -Database $detachattachdb
            $db1.Name | Should -Be $detachattachdb
            $db2.Name | Should -Be $detachattachdb
        }

        It "Name, recovery model, and status should match" {
            $db1 = Get-DbaDatabase -SqlInstance $global:instance2 -Database $detachattachdb
            $db2 = Get-DbaDatabase -SqlInstance $global:instance3 -Database $detachattachdb
            $db1.Name | Should -Be $db2.Name
            $db1.RecoveryModel | Should -Be $db2.RecoveryModel
            $db1.Status | Should -Be $db2.Status
            $db1.Owner | Should -Be $db2.Owner
        }

        It "Should say skipped" {
            $results = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $detachattachdb -DetachAttach -Reattach
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "Already exists on destination"
        }
    }

    Context "Backup restore" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2, $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $results = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb -BackupRestore -SharedPath $NetworkPath
        }

        It "copies a database successfully" {
            $results.Name | Should -Be $backuprestoredb
            $results.Status | Should -Be "Successful"
        }

        It "retains its name, recovery model, and status." {
            $dbs = Get-DbaDatabase -SqlInstance $global:instance2, $global:instance3 -Database $backuprestoredb
            $dbs[0].Name | Should -Not -BeNullOrEmpty
            $dbs[0].Name | Should -Be $dbs[1].Name
            $dbs[0].RecoveryModel | Should -Be $dbs[1].RecoveryModel
            $dbs[0].Status | Should -Be $dbs[1].Status
            $dbs[0].Owner | Should -Be $dbs[1].Owner
        }

        It "Should say skipped" {
            $result = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb2 -BackupRestore -SharedPath $NetworkPath
            $result.Status | Should -Be "Skipped"
            $result.Notes | Should -Be "Already exists on destination"
        }

        It "Should overwrite when forced to" -Skip:$env:appveyor {
            $result = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb2 -BackupRestore -SharedPath $NetworkPath -Force
            $result.Status | Should -Be "Successful"
        }
    }

    Context "UseLastBackup - read backup history" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2, $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance3 -Database $backuprestoredb
        }

        It "copies a database successfully using backup history" {
            $results = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb -BackupRestore -UseLastBackup
            $results.Name | Should -Be $backuprestoredb
            $results.Status | Should -Be "Successful"
        }

        It "retains its name, recovery model, and status." {
            $dbs = Get-DbaDatabase -SqlInstance $global:instance2, $global:instance3 -Database $backuprestoredb
            $dbs[0].Name | Should -Not -BeNullOrEmpty
            $dbs[0].Name | Should -Be $dbs[1].Name
            $dbs[0].RecoveryModel | Should -Be $dbs[1].RecoveryModel
            $dbs[0].Status | Should -Be $dbs[1].Status
            $dbs[0].Owner | Should -Be $dbs[1].Owner
        }
    }

    Context "UseLastBackup with -Continue" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2, $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance3 -Database $backuprestoredb
            $null = Get-DbaDbBackupHistory -SqlInstance $global:instance2 -Database $backuprestoredb -LastFull | Restore-DbaDatabase -SqlInstance $global:instance3 -DatabaseName $backuprestoredb -NoRecovery
            $null = Backup-DbaDatabase -SqlInstance $global:instance2 -Database $backuprestoredb -BackupDirectory $NetworkPath -Type Diff
        }

        It "continues the restore over existing database using backup history" {
            $results = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb -BackupRestore -UseLastBackup -Continue
            $results.Name | Should -Be $backuprestoredb
            $results.Status | Should -Be "Successful"
        }

        It "retains its name, recovery model, and status." {
            $dbs = Get-DbaDatabase -SqlInstance $global:instance2, $global:instance3 -Database $backuprestoredb
            $dbs[0].Name | Should -Not -BeNullOrEmpty
            $dbs[0].Name | Should -Be $dbs[1].Name
            $dbs[0].RecoveryModel | Should -Be $dbs[1].RecoveryModel
            $dbs[0].Status | Should -Be $dbs[1].Status
            $dbs[0].Owner | Should -Be $dbs[1].Owner
        }
    }

    Context "Copying with renames using backup/restore" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2, $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Get-DbaDatabase -SqlInstance $global:instance3 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }

        AfterAll {
            Get-DbaProcess -SqlInstance $global:instance2, $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Get-DbaDatabase -SqlInstance $global:instance3 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }

        It "Should have renamed a single db" {
            $newname = "copy$(Get-Random)"
            $results = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb -BackupRestore -SharedPath $NetworkPath -NewName $newname
            $results[0].DestinationDatabase | Should -Be $newname
            $files = Get-DbaDbFile -Sqlinstance $global:instance3 -Database $newname
            ($files.PhysicalName -like "*$newname*").count | Should -Be $files.count
        }

        It "Should warn if trying to rename and prefix" {
            $null = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb -BackupRestore -SharedPath $NetworkPath -NewName $newname -prefix pre -WarningVariable warnvar
            $warnvar | Should -BeLike "*NewName and Prefix are exclusive options, cannot specify both"
        }

        It "Should prefix databasename and files" {
            $prefix = "da$(Get-Random)"
            $results = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb -BackupRestore -SharedPath $NetworkPath -Prefix $prefix
            $results[0].DestinationDatabase | Should -Be "$prefix$backuprestoredb"
            $files = Get-DbaDbFile -Sqlinstance $global:instance3 -Database "$prefix$backuprestoredb"
            ($files.PhysicalName -like "*$prefix$backuprestoredb*").count | Should -Be $files.count
        }
    }

    Context "Copying with renames using detachattach" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2, $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance3 -Database $backuprestoredb
        }

        It "Should have renamed a single db" {
            $newname = "copy$(Get-Random)"
            $results = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb -DetachAttach -NewName $newname -Reattach
            $results[0].DestinationDatabase | Should -Be $newname
            $files = Get-DbaDbFile -Sqlinstance $global:instance3 -Database $newname
            ($files.PhysicalName -like "*$newname*").count | Should -Be $files.count
            $null = Remove-DbaDatabase -SqlInstance $global:instance3 -Database $newname
        }

        It "Should prefix databasename and files" {
            $prefix = "copy$(Get-Random)"
            $results = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb -DetachAttach -Reattach -Prefix $prefix
            $results[0].DestinationDatabase | Should -Be "$prefix$backuprestoredb"
            $files = Get-DbaDbFile -Sqlinstance $global:instance3 -Database "$prefix$backuprestoredb"
            ($files.PhysicalName -like "*$prefix$backuprestoredb*").count | Should -Be $files.count
            $null = Remove-DbaDatabase -SqlInstance $global:instance3 -Database "$prefix$backuprestoredb"
        }

        It "Should warn and exit if newname and >1 db specified" {
            $null = Restore-DbaDatabase -SqlInstance $global:instance2 -path $global:appveyorlabrepo\RestoreTimeClean2016 -useDestinationDefaultDirectories
            $null = Copy-DbaDatabase -Source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb, RestoreTimeClean -DetachAttach -Reattach -NewName warn -WarningVariable warnvar
            $warnvar | Should -BeLike "*Cannot use NewName when copying multiple databases"
            $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database RestoreTimeClean
        }
    }

    Context "Copying via Azure storage" -Skip:(-not $env:azurepasswd) {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2, $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance3 -Database $backuprestoredb
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $sql = "CREATE CREDENTIAL [$global:azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
            $server.Query($sql)
            $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$global:azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
            $server.Query($sql)
            $server3 = Connect-DbaInstance -SqlInstance $global:instance3
            $sql = "CREATE CREDENTIAL [$global:azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
            $server3.Query($sql)
            $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$global:azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
            $server3.Query($sql)
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $global:instance3 -Database $backuprestoredb | Remove-DbaDatabase -Confirm:$false
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $server.Query("DROP CREDENTIAL [$global:azureblob]")
            $server.Query("DROP CREDENTIAL dbatools_ci")
            $server = Connect-DbaInstance -SqlInstance $global:instance3
            $server.Query("DROP CREDENTIAL [$global:azureblob]")
            $server.Query("DROP CREDENTIAL dbatools_ci")
        }

        It "Should Copy $backuprestoredb via Azure legacy credentials" {
            $results = Copy-DbaDatabase -source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb -BackupRestore -SharedPath $global:azureblob -AzureCredential dbatools_ci
            $results[0].Name | Should -Be $backuprestoredb
            $results[0].Status | Should -BeLike 'Successful*'
        }

        It "Should Copy $backuprestoredb via Azure new credentials" {
            Start-Sleep -Seconds 60
            $results = Copy-DbaDatabase -source $global:instance2 -Destination $global:instance3 -Database $backuprestoredb -Newname djkhgfkjghfdjgd -BackupRestore -SharedPath $global:azureblob
            $results[0].Name | Should -Be $backuprestoredb
            $results[0].DestinationDatabase | Should -Be 'djkhgfkjghfdjgd'
            $results[0].Status | Should -BeLike 'Successful*'
        }
    }
}

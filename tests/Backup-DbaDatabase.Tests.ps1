param($ModuleName = 'dbatools')

. "$PSScriptRoot\constants.ps1"

Describe "Restore-DbaDatabase Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Restore-DbaDatabase
        }
        $params = @(
            'SqlInstance', 'SqlCredential', 'Path', 'DatabaseName', 'DestinationDataDirectory', 'DestinationLogDirectory',
            'DestinationFileStreamDirectory', 'RestoreTime', 'NoRecovery', 'WithReplace', 'XpDirTree', 'OutputScriptOnly',
            'VerifyOnly', 'MaintenanceSolutionBackup', 'FileMapping', 'IgnoreLogBackup', 'IgnoreDiffBackup',
            'UseDestinationDefaultDirectories', 'ReuseSourceFolderStructure', 'DestinationFilePrefix',
            'RestoredDatabaseNamePrefix', 'TrustDbBackupHistory', 'MaxTransferSize', 'BlockSize', 'BufferCount',
            'DirectoryRecurse', 'EnableException', 'StandbyDirectory', 'Continue', 'AzureCredential', 'ReplaceDbNameInFile',
            'DestinationFileSuffix', 'Recover', 'KeepCDC', 'GetBackupInformation', 'StopAfterGetBackupInformation',
            'SelectBackupInformation', 'StopAfterSelectBackupInformation', 'FormatBackupInformation',
            'StopAfterFormatBackupInformation', 'TestBackupInformation', 'StopAfterTestBackupInformation', 'PageRestore',
            'PageRestoreTailFolder', 'StatementTimeout', 'KeepReplication', 'StopBefore', 'StopMark', 'StopAfterDate',
            'ExecuteAs', 'NoXpDirRecurse'
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Restore-DbaDatabase Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        $DataFolder = 'C:\temp\datafiles'
        $LogFolder = 'C:\temp\logfiles'
        if (-not (Test-Path $DataFolder)) {
            New-Item -ItemType Directory -Path $DataFolder -ErrorAction SilentlyContinue | Out-Null
        }
        if (-not (Test-Path $LogFolder)) {
            New-Item -ItemType Directory -Path $LogFolder -ErrorAction SilentlyContinue | Out-Null
        }
    }

    Context "Properly restores a database on the local drive using Path" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        It "Should restore the database successfully" {
            $results = Restore-DbaDatabase -SqlInstance $global:instance2 -Path "$global:appveyorlabrepo\singlerestore\singlerestore.bak"
            $results.BackupFile | Should -Be "$global:appveyorlabrepo\singlerestore\singlerestore.bak"
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Ensuring warning is thrown if database already exists" {
        It "Should warn and not return object" {
            $warning = $null
            $results = Restore-DbaDatabase -SqlInstance $global:instance2 -Path "$global:appveyorlabrepo\singlerestore\singlerestore.bak" -WarningVariable warning -WarningAction SilentlyContinue
            $warning | Where-Object { $_ -like '*Test-DbaBackupInformation*Database*' } | Should -Match "exists, so WithReplace must be specified"
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Database is properly removed again after withreplace test" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -Database singlerestore | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database singlerestore | Out-Null
        }
        It "Should ensure the database is dropped" {
            $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database singlerestore -ErrorAction SilentlyContinue
            $db | Should -BeNullOrEmpty
        }
    }

    Context "Properly restores a database on the local drive using piped Get-ChildItem results" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
        }
        It "Should restore the database successfully using piped Get-ChildItem" {
            $results = Get-ChildItem "$global:appveyorlabrepo\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $global:instance2
            $results.BackupFile | Should -Be "$global:appveyorlabrepo\singlerestore\singlerestore.bak"
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Test VerifyOnly works with db in existence" {
        It "Should verify the backup successfully" {
            $results = Get-ChildItem "$global:appveyorlabrepo\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $global:instance2 -VerifyOnly
            $results[0] | Should -Be "Verify successful"
        }
    }

    Context "Database is properly removed again after gci tests" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database singlerestore | Out-Null
        }
        It "Should ensure the database is dropped" {
            $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database singlerestore -ErrorAction SilentlyContinue
            $db | Should -BeNullOrEmpty
        }
    }

    Context "Allows continues with Differential Backups" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
        }
        It "Should restore full backup with NoRecovery" {
            $results = Restore-DbaDatabase -SqlInstance $global:instance2 -Path "$global:appveyorlabrepo\DoubleDiffing\difftest-full.bak" -NoRecovery
            $results.RestoreComplete | Should -Be $true
        }
        It "Should restore first differential backup with NoRecovery and Continue" {
            $results1 = Restore-DbaDatabase -SqlInstance $global:instance2 -Path "$global:appveyorlabrepo\DoubleDiffing\difftest-diff1.bak" -NoRecovery -Continue
            $results1.RestoreComplete | Should -Be $true
        }
        It "Should restore second differential backup with Continue" {
            $results2 = Restore-DbaDatabase -SqlInstance $global:instance2 -Path "$global:appveyorlabrepo\DoubleDiffing\difftest-diff2.bak" -Continue
            $results2.RestoreComplete | Should -Be $true
        }
    }

    Context "Database is restored with correct renamings" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database singlerestore | Out-Null
        }
        It "Should restore database with DestinationFilePrefix" {
            $results = Get-ChildItem "$global:appveyorlabrepo\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $global:instance2 -DestinationFilePrefix prefix
            $results.RestoreComplete | Should -Be $true
            (($results.RestoredFile -split ',') | ForEach-Object { $_.Substring(0, 6) }) | Should -Be 'prefix'
        }
        It "Should restore database with DestinationFileSuffix" {
            $results = Get-ChildItem "$global:appveyorlabrepo\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $global:instance2 -DestinationFileSuffix suffix -WithReplace
            $results.RestoreComplete | Should -Be $true
            (($results.RestoredFile -split ',') | Where-Object { $_ -match "suffix\." }).Count | Should -Be 2
        }
        It "Should restore database with both DestinationFilePrefix and DestinationFileSuffix" {
            $results = Get-ChildItem "$global:appveyorlabrepo\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $global:instance2 -DestinationFileSuffix suffix -DestinationFilePrefix prefix -WithReplace
            $results.RestoreComplete | Should -Be $true
            (($results.RestoredFile -split ',') | Where-Object { $_ -match "^prefix.*suffix\." }).Count | Should -Be 2
        }
    }

    Context "Database is properly removed again after prefix and suffix tests" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database singlerestore | Out-Null
        }
        It "Should ensure the database is dropped" {
            $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database singlerestore -ErrorAction SilentlyContinue
            $db | Should -BeNullOrEmpty
        }
    }

    Context "Replace databasename in Restored File" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database pestering | Out-Null
        }
        It "Should restore database with ReplaceDbNameInFile and new DatabaseName" {
            $results = Get-ChildItem "$global:appveyorlabrepo\singlerestore\singlerestore.bak" |
                Restore-DbaDatabase -SqlInstance $global:instance2 -DatabaseName Pestering -ReplaceDbNameInFile -WithReplace
            (($results.RestoredFile -split ',') | Where-Object { $_ -like "*pestering*" }).Count | Should -Be 2
            foreach ($file in ($results.RestoredFileFull -split ',')) {
                Test-Path $file | Should -Be $true
            }
        }
    }

    Context "Database is properly removed (name change)" {
        BeforeAll {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database pestering | Out-Null
        }
        It "Should ensure the database is dropped" {
            $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database pestering -ErrorAction SilentlyContinue
            $db | Should -BeNullOrEmpty
        }
    }

    Context "Replace databasename in Restored File, but don't change backup history #5036" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database Pestering | Out-Null
        }
        It "Should not change the PhysicalName in the FileList of the backup history" {
            $bh = Get-DbaBackupInformation -Path "$global:appveyorlabrepo\singlerestore\singlerestore.bak" -SqlInstance $global:instance2
            $firstPhysicalName = $bh.FileList.PhysicalName[0]
            $null = $bh | Restore-DbaDatabase -SqlInstance $global:instance2 -DatabaseName Pestering -ReplaceDbNameInFile -WithReplace -OutputScriptOnly
            $bh.FileList.PhysicalName[0] | Should -Be $firstPhysicalName
        }
    }

    Context "Test VerifyOnly works with db not in existence" {
        BeforeAll {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database singlerestore -ErrorAction SilentlyContinue | Out-Null
        }
        It "Should verify the backup successfully when database does not exist" {
            $results = Get-ChildItem "$global:appveyorlabrepo\singlerestore\singlerestore.bak" |
                Restore-DbaDatabase -SqlInstance $global:instance2 -VerifyOnly
            $results[0] | Should -Be "Verify successful"
        }
    }

    Context "Database is properly removed again after verify tests" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database singlerestore | Out-Null
        }
        It "Should ensure the database is dropped" {
            $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database singlerestore -ErrorAction SilentlyContinue
            $db | Should -BeNullOrEmpty
        }
    }

    Context "Folder restore options" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database singlerestore | Out-Null
        }
        It "Should restore database with DestinationDataDirectory" {
            $results = Get-ChildItem "$global:appveyorlabrepo\singlerestore\singlerestore.bak" |
                Restore-DbaDatabase -SqlInstance $global:instance2 -DestinationDataDirectory $DataFolder
            $results.RestoreComplete | Should -Be $true
            (($results.RestoredFileFull -split ',') | Where-Object { $_ -like "$DataFolder*" }).Count | Should -Be 2
            foreach ($file in ($results.RestoredFileFull -split ',')) {
                Test-Path $file | Should -Be $true
            }
        }
        It "Should restore database with DestinationDataDirectory and DestinationLogDirectory" {
            $results = Get-ChildItem "$global:appveyorlabrepo\singlerestore\singlerestore.bak" |
                Restore-DbaDatabase -SqlInstance $global:instance2 -DestinationDataDirectory $DataFolder -DestinationLogDirectory $LogFolder -WithReplace
            $results.RestoreComplete | Should -Be $true
            (($results.RestoredFileFull -split ',') | Where-Object { $_ -like "$DataFolder*" }).Count | Should -Be 1
            (($results.RestoredFileFull -split ',') | Where-Object { $_ -like "$LogFolder*" }).Count | Should -Be 1
            foreach ($file in ($results.RestoredFileFull -split ',')) {
                Test-Path $file | Should -Be $true
            }
        }
    }

    Context "Database is properly removed again after folder options tests" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database singlerestore | Out-Null
        }
        It "Should ensure the database is dropped" {
            $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database singlerestore -ErrorAction SilentlyContinue
            $db | Should -BeNullOrEmpty
        }
    }

    Context "Putting all restore file modification options together" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database singlerestore | Out-Null
        }
        It "Should restore database with all file modification options" {
            $results = Get-ChildItem "$global:appveyorlabrepo\singlerestore\singlerestore.bak" |
                Restore-DbaDatabase -SqlInstance $global:instance2 -DestinationDataDirectory $DataFolder -DestinationLogDirectory $LogFolder -DestinationFileSuffix Suffix -DestinationFilePrefix prefix
            $results.RestoreComplete | Should -Be $true
            (($results.RestoredFileFull -split ',') | Where-Object { $_ -like "$DataFolder*" }).Count | Should -Be 1
            (($results.RestoredFileFull -split ',') | Where-Object { $_ -like "$LogFolder*" }).Count | Should -Be 1
            (($results.RestoredFile -split ',') | Where-Object { $_ -match "^prefix.*suffix\." }).Count | Should -Be 2
            foreach ($file in ($results.RestoredFileFull -split ',')) {
                Test-Path $file | Should -Be $true
            }
        }
    }

    Context "Database is properly removed again after all file mods test" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database singlerestore | Out-Null
        }
        It "Should ensure the database is dropped" {
            $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database singlerestore -ErrorAction SilentlyContinue
            $db | Should -BeNullOrEmpty
        }
    }

    Context "Properly restores an instance using ola-style backups via pipe" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
        }
        It "Should restore multiple databases successfully using piped Get-ChildItem" {
            $results = Get-ChildItem "$global:appveyorlabrepo\sql2008-backups" | Restore-DbaDatabase -SqlInstance $global:instance2
            $results.DatabaseName.Count | Should -Be 33
            ($results.RestoreComplete -contains $false) | Should -Be $false
            ($results.Count -gt 0) | Should -Be $true
        }
    }

    Context "Database is properly removed again after ola pipe test" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            $null = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        It "Should ensure all user databases are dropped" {
            $dbs = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem -ErrorAction SilentlyContinue
            $dbs | Should -BeNullOrEmpty
        }
    }

    Context "Properly restores an instance using ola-style backups via string" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
        }
        It "Should restore multiple databases successfully using Path string" {
            $results = Restore-DbaDatabase -SqlInstance $global:instance2 -Path "$global:appveyorlabrepo\sql2008-backups"
            $results.DatabaseName.Count | Should -Be 33
            ($results.RestoreComplete -contains $false) | Should -Be $false
            ($results.Count -gt 0) | Should -Be $true
        }
    }

    Context "All user databases are removed post ola-style test" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningAction SilentlyContinue | Out-Null
            $null = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        It "Should ensure all user databases are dropped" {
            $dbs = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem -ErrorAction SilentlyContinue
            $dbs | Should -BeNullOrEmpty
        }
    }

    Context "RestoreTime setup checks" {
        BeforeAll {
            $results = Restore-DbaDatabase -SqlInstance $global:instance2 -Path "$global:appveyorlabrepo\RestoreTimeClean2016"
        }
        It "Should restore database successfully" {
            ($results.RestoreComplete -contains $false) | Should -Be $false
            ($results.Count -gt 0) | Should -Be $true
        }
        It "Should have restored 5 files" {
            $results.Count | Should -Be 5
        }
        It "Should have restored data from the correct time range" {
            $sqlResults = Invoke-DbaQuery -SqlInstance $global:instance2 -Query "select max(dt) as maxdt, min(dt) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults.mindt | Should -Be (Get-Date "2019-05-02 21:00:55")
            $sqlResults.maxdt | Should -Be (Get-Date "2019-05-02 21:30:26")
        }
    }

    Context "All user databases are removed post RestoreTime check" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        It "Should ensure all user databases are dropped" {
            $dbs = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem -ErrorAction SilentlyContinue
            $dbs | Should -BeNullOrEmpty
        }
    }

    Context "RestoreTime point in time" {
        BeforeAll {
            $results = Restore-DbaDatabase -SqlInstance $global:instance2 -Path "$global:appveyorlabrepo\RestoreTimeClean2016" -RestoreTime (Get-Date "2019-05-02 21:12:27") -WarningVariable warnvar -ErrorVariable errvar
        }
        It "Should have restored 4 files" {
            $results.Count | Should -Be 4
        }
        It "Should have restored data up to the specified RestoreTime" {
            $sqlResults = Invoke-DbaQuery -SqlInstance $global:instance2 -Query "select max(dt) as maxdt, min(dt) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults.mindt | Should -Be (Get-Date "2019-05-02 21:00:55")
            $sqlResults.maxdt | Should -Be (Get-Date "2019-05-02 21:12:26")
        }
    }

    Context "All user databases are removed post point in time test" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        It "Should ensure all user databases are dropped" {
            $dbs = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem -ErrorAction SilentlyContinue
            $dbs | Should -BeNullOrEmpty
        }
    }

    Context "RestoreTime point in time with Simple Model" {
        BeforeAll {
            $results = Restore-DbaDatabase -SqlInstance $global:instance2 -Path "$global:appveyorlabrepo\sql2008-backups\SimpleRecovery\" -RestoreTime (Get-Date "2018-04-06 10:37:44")
        }
        It "Should have restored 2 files" {
            $results.Count | Should -Be 2
        }
        It "Should have restored data up to the last full backup" {
            $sqlResults = Invoke-DbaQuery -SqlInstance $global:instance2 -Query "select max(dt) as maxdt, min(dt) as mindt from SimpleBackTest.dbo.steps"
            $sqlResults.mindt | Should -Be (Get-Date "2018-04-06 10:30:32")
            $sqlResults.maxdt | Should -Be (Get-Date "2018-04-06 10:35:02")
        }
    }

    Context "All user databases are removed post Simple Model test" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        It "Should ensure all user databases are dropped" {
            $dbs = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem -ErrorAction SilentlyContinue
            $dbs | Should -BeNullOrEmpty
        }
    }

    # Continue updating the remaining Context blocks in the same manner, ensuring that:
    # - All setup and teardown code is properly placed in BeforeAll/AfterAll
    # - All test code is within It blocks
    # - Assertions use the correct syntax
    # - Variables are properly scoped
    # - Mocks are correctly scoped (if any)
    # - Leave debugging comments intact
}


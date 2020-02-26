$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'DatabaseName', 'DestinationDataDirectory', 'DestinationLogDirectory', 'DestinationFileStreamDirectory', 'RestoreTime', 'NoRecovery', 'WithReplace', 'XpDirTree', 'OutputScriptOnly', 'VerifyOnly', 'MaintenanceSolutionBackup', 'FileMapping', 'IgnoreLogBackup', 'UseDestinationDefaultDirectories', 'ReuseSourceFolderStructure', 'DestinationFilePrefix', 'RestoredDatabaseNamePrefix', 'TrustDbBackupHistory', 'MaxTransferSize', 'BlockSize', 'BufferCount', 'DirectoryRecurse', 'EnableException', 'StandbyDirectory', 'Continue', 'AzureCredential', 'ReplaceDbNameInFile', 'DestinationFileSuffix', 'Recover', 'KeepCDC', 'GetBackupInformation', 'StopAfterGetBackupInformation', 'SelectBackupInformation', 'StopAfterSelectBackupInformation', 'FormatBackupInformation', 'StopAfterFormatBackupInformation', 'TestBackupInformation', 'StopAfterTestBackupInformation', 'PageRestore', 'PageRestoreTailFolder', 'StatementTimeout', 'KeepReplication'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    # $script:instance3 to add to the 2016_2017 matrix
    #Setup variable for multiple contexts
    $DataFolder = 'c:\temp\datafiles'
    $LogFolder = 'C:\temp\logfiles'
    New-Item -ItemType Directory $DataFolder -ErrorAction SilentlyContinue
    New-Item -ItemType Directory $LogFolder -ErrorAction SilentlyContinue

    Context "Properly restores a database on the local drive using Path" {
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak
        It "Should Return the proper backup file location" {
            $results.BackupFile | Should Be "$script:appveyorlabrepo\singlerestore\singlerestore.bak"
        }
        It "Should return successful restore" {
            $results.RestoreComplete | Should Be $true
        }
    }

    Context "Ensuring warning is thrown if database already exists" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -WarningVariable warning -WarningAction SilentlyContinue
        It "Should warn" {
            $warning | Where-Object { $_ -like '*Test-DbaBackupInformation*Database*' } | Should Match "exists, so WithReplace must be specified"
        }
        It "Should not return object" {
            $results | Should Be $null
        }
    }

    Context "Database is properly removed again after withreplace test" {
        Get-DbaProcess $script:instance2 -Database singlerestore | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database singlerestore
        Get-DbaProcess $script:instance2 -Database singlerestore | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status -eq "Dropped" -or $results.Status -eq $null
        }
    }

    Get-DbaProcess $script:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Context "Properly restores a database on the local drive using piped Get-ChildItem results" {
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance2
        It "Should Return the proper backup file location" {
            $results.BackupFile | Should Be "$script:appveyorlabrepo\singlerestore\singlerestore.bak"
        }
        It "Should return successful restore" {
            $results.RestoreComplete | Should Be $true
        }
    }

    Context "Test VerifyOnly works with db in existence" {
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance2 -VerifyOnly
        It "Should have verified Successfully" {
            $results[0] | Should Be "Verify successful"
        }
    }

    Get-DbaProcess $script:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Context "Database is properly removed again after gci tests" {
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }

    Context "Allows continues with Differential Backups" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\DoubleDiffing\difftest-full.bak -NoRecovery
        It "Should restore the root full cleanly" {
            $results.RestoreComplete | Should -Be $True
        }
        $results1 = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\DoubleDiffing\difftest-diff1.bak -NoRecovery -Continue
        It "Should restore the first diff cleanly" {
            $results1.RestoreComplete | Should -Be $True
        }
        $results2 = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\DoubleDiffing\difftest-diff2.bak -Continue
        It "Should restore the second diff cleanly" {
            $results2.RestoreComplete | Should -Be $True
        }

    }

    Get-DbaProcess $script:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Clear-DbaConnectionPool
    Start-Sleep -Seconds 2

    Context "Database is restored with correct renamings" {
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance2 -DestinationFilePrefix prefix
        It "Should return successful restore with prefix" {
            $results.RestoreComplete | Should Be $true
        }
        It "Should return the 2 prefixed files" {
            (($results.RestoredFile -split ',').substring(0, 6) -eq 'prefix').count | Should be 2
        }
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance2 -DestinationFileSuffix suffix -WithReplace
        It "Should return successful restore with suffix" {
            ($results.RestoreComplete -eq $true) | Should Be $true
        }
        It "Should return the 2 suffixed files" {
            (($Results.RestoredFile -split ',') -match "suffix\.").count | Should be 2
        }
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance2 -DestinationFileSuffix suffix -DestinationFilePrefix prefix -WithReplace
        It "Should return successful restore with suffix and prefix" {
            ($results.RestoreComplete -eq $true) | Should Be $true
        }
        It "Should return the 2 prefixed and suffixed files" {
            (($Results.RestoredFile -split ',') -match "^prefix.*suffix\.").count | Should be 2
        }
    }

    Get-DbaProcess $script:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Context "Database is properly removed again post prefix and suffix tests" {
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }

    }

    Context "Replace databasename in Restored File" {
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance2 -DatabaseName Pestering -replaceDbNameInFile -WithReplace
        It "Should return the 2 files swapping singlerestore for pestering (output)" {
            (($Results.RestoredFile -split ',') -like "*pestering*").count | Should be 2
        }
        ForEach ($file in ($results.RestoredFileFull -split ',')) {
            It "$file Should exist on Filesystem" {
                $file | Should Exist
            }
        }
    }

    Context "Database is properly removed (name change)" {
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database pestering
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }

    Get-DbaProcess $script:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Clear-DbaConnectionPool
    Start-Sleep -Seconds 2

    Context "Folder restore options" {
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance2 -DestinationDataDirectory $DataFolder
        It "Should return successful restore with DestinationDataDirectory" {
            $results.RestoreComplete | Should Be $true
        }
        It "Should have moved all files to $DataFolder" {
            (($results.RestoredFileFull -split ',') -like "$DataFolder*").count | Should be 2
        }
        ForEach ($file in ($results.RestoredFileFull -split ',')) {
            It "$file Should exist on Filesystem" {
                $file | Should Exist
            }
        }

        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance2 -DestinationDataDirectory $DataFolder -DestinationLogDirectory $LogFolder -WithReplace
        It "Should have moved data file to $DataFolder" {
            (($results.RestoredFileFull -split ',') -like "$DataFolder*").count | Should be 1
        }
        It "Should have moved Log file to $LogFolder" {
            (($results.RestoredFileFull -split ',') -like "$LogFolder*").count | Should be 1
        }
        ForEach ($file in ($results.RestoredFileFull -split ',')) {
            It "$file Should exist on Filesystem" {
                $file | Should Exist
            }
        }
    }

    Context "Database is properly removed again after folder options tests" {
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }

    Clear-DbaConnectionPool
    Start-Sleep -Seconds 2
    Context "Putting all restore file modification options together" {
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance2 -DestinationDataDirectory $DataFolder -DestinationLogDirectory $LogFolder -DestinationFileSuffix Suffix -DestinationFilePrefix prefix
        It "Should return successful restore with all file mod options" {
            $results.RestoreComplete | Should Be $true
        }
        It "Should have moved data file to $DataFolder (output)" {
            (($results.RestoredFileFull -split ',') -like "$DataFolder*").count | Should be 1
        }
        It "Should have moved Log file to $LogFolder (output)" {
            (($results.RestoredFileFull -split ',') -like "$LogFolder*").count | Should be 1
        }
        It "Should return the 2 prefixed and suffixed files" {
            (($Results.RestoredFile -split ',') -match "^prefix.*suffix\.").count | Should be 2
        }
        ForEach ($file in ($results.RestoredFileFull -split ',')) {
            It "$file Should exist on Filesystem" {
                $file | Should Exist
            }
        }
    }

    Clear-DbaConnectionPool

    Start-Sleep -Seconds 1
    Context "Database is properly removed again after all file mods test" {
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }

    Get-DbaProcess $script:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Clear-DbaConnectionPool
    Start-Sleep -Seconds 5
    Clear-DbaConnectionPool

    Context "Properly restores an instance using ola-style backups via pipe" {
        $results = Get-ChildItem $script:appveyorlabrepo\sql2008-backups | Restore-DbaDatabase -SqlInstance $script:instance2
        It "Restored files count should be the right number" {
            $results.DatabaseName.Count | Should Be 28
        }
        It "Should return successful restore" {
            ($results.RestoreComplete -contains $false) | Should Be $false
            ($results.count -gt 0) | Should be $True
        }
    }

    Context "Should proceed if backups from multiple dbs passed in and databasename specified" {
        $results = Get-ChildItem $script:appveyorlabrepo\sql2008-backups | Restore-DbaDatabase -SqlInstance $script:instance2 -DatabaseName test -WarningVariable warnvar
        It "Should return nothing" {
            $null -eq $results | Should be $True
        }

        It "Should have warned with the correct error" {
            $warnvar -like "*Multiple Databases' backups passed in, but only 1 name to restore them under. Stopping as cannot work out how to proceed*" | Should Be $True
        }
    }

    Context "Database is properly removed again after ola pipe test" {
        Get-DbaProcess $script:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        Get-DbaProcess $script:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false

        It "Should say the status was dropped or null" {
            foreach ($result in $results) {
                $result.Status -eq "Dropped" -or $result.Status -eq $null
            }
        }
    }

    Context "Properly restores an instance using ola-style backups via string" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\sql2008-backups
        It "Restored files count should be the right number" {
            $results.DatabaseName.Count | Should Be 28
        }
        It "Should return successful restore" {
            ($results.RestoreComplete -contains $false) | Should Be $false
            ($results.count -gt 0) | Should be $True
        }
    }

    Get-DbaProcess $script:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue

    Context "All user databases are removed post ola-style test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        It -Skip "Should say the status was dropped" {
            $results | ForEach-Object { $_.Status | Should Be "Dropped" }
        }
    }

    Get-DbaProcess $script:instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Clear-DbaConnectionPool
    Start-Sleep -Seconds 2

    Context "RestoreTime setup checks" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -path $script:appveyorlabrepo\RestoreTimeClean2016
        $sqlResults = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
        It "Should restore cleanly" {
            ($results.RestoreComplete -contains $false) | Should Be $false
            ($results.count -gt 0) | Should be $True
        }
        It "Should have restored 5 files" {
            $results.count | Should be 5
        }
        It "Should have restored from 2019-05-02 21:00:55" {
            $sqlResults.mindt | Should be (get-date "2019-05-02 21:00:55")
        }
        It "Should have restored to 2019-05-02 13:28:43" {
            $sqlResults.maxdt | Should be (get-date "2019-05-02 21:30:26")
        }
    }

    Clear-DbaConnectionPool
    Start-Sleep -Seconds 1

    Context "All user databases are removed post RestoreTime check" {
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Clear-DbaConnectionPool
    Start-Sleep -Seconds 1

    Context "RestoreTime point in time" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -path $script:appveyorlabrepo\RestoreTimeClean2016 -RestoreTime (get-date "2019-05-02 21:12:27") -WarningVariable warnvar -ErrorVariable errvar
        $sqlResults = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
        It "Should have restored 4 files" {
            $results.count | Should be 4
        }
        It "Should have restored from 2019-05-02 21:00:55" {
            $sqlResults.mindt | Should be (get-date "2019-05-02 21:00:55")
        }
        It "Should have restored to 2019-05-02 21:12:26" {
            $sqlResults.maxdt | Should be (get-date "2019-05-02 21:12:26")
        }
    }

    Context "All user databases are removed" {
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        It -Skip "Should say the status was dropped post point in time test" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Clear-DbaConnectionPool
    Start-Sleep -Seconds 1

    Context "RestoreTime point in time with Simple Model" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -path $script:appveyorlabrepo\sql2008-backups\SimpleRecovery\ -RestoreTime (get-date "2018-04-06 10:37:44")
        $sqlResults = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from SimpleBackTest.dbo.steps"

        It "Should have restored 2 files" {
            $results.count | Should be 2
        }
        It "Should have restored from 2018-04-06 10:30:32" {
            $sqlResults.mindt | Should be (get-date "2018-04-06 10:30:32")
        }
        It "Should have restored to 2018-04-06 10:35:02" {
            $sqlResults.maxdt | Should be (get-date "2018-04-06 10:35:02")
        }
    }

    Context "All user databases are removed" {
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped post point in time test" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Clear-DbaConnectionPool
    Start-Sleep -Seconds 1

    Context "RestoreTime point in time and continue" {
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        $Should_Run = (Connect-DbaInstance -SqlInstance $script:instance2).Version.ToString() -like '13.*'
        if (-not ($Should_Run)) {
            It "The test can run" {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
            }
            return
        }
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -path $script:appveyorlabrepo\RestoreTimeClean2016 -RestoreTime (get-date "2019-05-02 21:12:27") -StandbyDirectory c:\temp -WarningVariable warnvar -ErrorVariable errvar -ErrorAction SilentlyContinue
        $sqlResults = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
        $warnvar
        It "Should not warn" {
            $null -eq (Get-Variable | Where-Object { $_.Name -eq 'warnvar' }) -or '' -eq $warnvar | Should Be $True
        }
        It "Should have restored 4 files" {
            $results.count | Should be 4
        }
        It "Should have restored from 05/02/2019 21:00:55" {
            $sqlResults.mindt | Should be (get-date "02 May 2019 21:00:55")
        }
        # Note, actual time is lower than target time due to how the db was built.
        It "Should have restored to 05/02/2019 21:12:26" {
            $sqlResults.maxdt | Should be (get-date "02 May 2019 21:12:26")
        }
        $results2 = Restore-DbaDatabase -SqlInstance $script:instance2 -path $script:appveyorlabrepo\RestoreTimeClean2016 -Continue
        $sqlResults2 = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
        It "Should have restored 4 files" {
            $results2.count | Should be 4
        }
        It "Should have restored from 02 May 2019 21:00:55" {
            $sqlResults2.mindt | Should be (get-date "02 May 2019 21:00:55")
        }
        It "Should have restored to 02 May 2019 21:30:26" {
            $sqlResults2.maxdt | Should be (get-date "02 May 2019 21:30:26")
        }

    }

    Context "RestoreTime point in time and continue with rename" {
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        $Should_Run = (Connect-DbaInstance -SqlInstance $script:instance2).Version.ToString() -like '13.*'
        if (-not ($Should_Run)) {
            It "The test can run" {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
            }
            return
        }
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Databasename contest -path $script:appveyorlabrepo\RestoreTimeClean2016 -RestoreTime (get-date "2019-05-02 21:23:58") -StandbyDirectory c:\temp
        $sqlResults = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from contest.dbo.steps"
        It "Should have restored 4 files" {
            $results.count | Should be 4
        }
        It "Should have restored from 05/02/2019 21:00:55" {
            $sqlResults.mindt | Should be (get-date "02 May 2019 21:00:55")
        }
        It "Should have restored to 05/02/2019 21:23:56" {
            $sqlResults.maxdt | Should be (get-date "02 May 2019 21:23:56")
        }
        $results2 = Restore-DbaDatabase -SqlInstance $script:instance2 -Databasename contest -path $script:appveyorlabrepo\RestoreTimeClean2016 -Continue
        $sqlResults2 = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from contest.dbo.steps"
        It "Should have restored 2 files" {
            $results2.count | Should be 2
        }
        It "Should have restored from 02 May 2019 21:00:55" {
            $sqlResults2.mindt | Should be (get-date "02 May 2019 21:00:55")
        }
        It "Should have restored to 02 May 2019 21:30:26" {
            $sqlResults2.maxdt | Should be (get-date "02 May 2019 21:30:26")
        }
    }

    Context "Continue Restore with Differentials" {
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        $Results = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\sql2008-backups\ft1\FULL\ -NoRecovery
        It "Should Have restored the database cleanly" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | Measure-Object).count -gt 0) | Should be $True
        }
        It "Should have left the db in a norecovery state" {
            (Get-DbaDatabase -SqlInstance $script:instance2 -Database ft1).Status | Should Be "Restoring"
        }
        $Results2 = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\sql2008-backups\ft1\ -Continue
        It "Should Have restored the database cleanly" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | Measure-Object).count -gt 0) | Should be $True
        }
        It "Should have recovered the database" {
            (Get-DbaDatabase -SqlInstance $script:instance2 -Database ft1).Status | Should Be "Normal"
        }
    }

    Context "Continue Restore with Differentials and rename " {
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        $Results = Restore-DbaDatabase -SqlInstance $script:instance2 -DatabaseName contest -Path $script:appveyorlabrepo\sql2008-backups\ft1\FULL\ -NoRecovery
        It "Should Have restored the database cleanly" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | Measure-Object).count -gt 0) | Should be $True
        }
        It "Should have left the db in a norecovery state" {
            (Get-DbaDatabase -SqlInstance $script:instance2 -Database contest).Status | Should Be "Restoring"
        }
        $Results2 = Restore-DbaDatabase -SqlInstance $script:instance2 -DatabaseName contest -Path $script:appveyorlabrepo\sql2008-backups\ft1\ -Continue
        It "Should Have restored the database cleanly" {
            ($results2.RestoreComplete -contains $false) | Should be $False
            (($results2 | Measure-Object).count -gt 0) | Should be $True
        }
        It "Should have recovered the database" {
            (Get-DbaDatabase -SqlInstance $script:instance2 -Database contest).Status | Should Be "Normal"
        }
    }

    Context "Continue Restore with multiple databases" {
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        }
        $files = @()
        $files += Get-ChildItem $script:appveyorlabrepo\sql2008-backups\db1\FULL\
        $files += Get-ChildItem $script:appveyorlabrepo\sql2008-backups\dbareports\FULL
        $Results = $files | Restore-DbaDatabase -SqlInstance $script:instance2  -NoRecovery
        It "Should Have restored the database cleanly" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | Measure-Object).count -gt 0) | Should be $True
        }
        It "Should have left the db in a norecovery state" {
            (Get-DbaDatabase -SqlInstance $script:instance2 | Where-Object { $_.Status -eq 'Recovering' }).count | Should Be 0
        }
        $files = @()
        $files += Get-ChildItem $script:appveyorlabrepo\sql2008-backups\db1\ -Recurse
        $files += Get-ChildItem $script:appveyorlabrepo\sql2008-backups\dbareports\ -Recurse
        $Results2 = $files | ? { $_.PsIsContainer -eq $false } | Restore-DbaDatabase -SqlInstance $script:instance2 -Continue
        It "Should Have restored the database cleanly" {
            ($results2.RestoreComplete -contains $false) | Should be $False
            (($results2 | Measure-Object).count -gt 0) | Should be $True
        }
        It "Should have recovered the database" {
            (Get-DbaDatabase -SqlInstance $script:instance2 | Where-Object { $_.Status -eq 'Recovering' }).count | Should Be 0
        }
    }

    Context "Backup DB For next test" {
        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -path $script:appveyorlabrepo\RestoreTimeClean2016\restoretimeclean.bak
        $results = Backup-DbaDatabase -SqlInstance $script:instance2 -Database RestoreTimeClean -BackupDirectory C:\temp
        It "Should return successful backup" {
            $results.BackupComplete | Should Be $true
        }
    }

    Context "All user databases are removed post continue test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Clear-DbaConnectionPool
    Start-Sleep -Seconds 1

    Get-DbaProcess $script:instance2 | Where-Object Program -match 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
    Context "Check Get-DbaDbBackupHistory pipes into Restore-DbaDatabase" {
        $history = Get-DbaDbBackupHistory -SqlInstance $script:instance2 -Database RestoreTimeClean -Last
        $results = $history | Restore-DbaDatabase -SqlInstance $script:instance2 -WithReplace -TrustDbBackupHistory
        It "Should have restored everything successfully" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | Measure-Object).count -gt 0) | Should be $True
        }
    }

    Clear-DbaConnectionPool
    Start-Sleep -Seconds 1

    Context "All user databases are removed post history test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Context "Restores a db with log and file files missing extensions" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -path $script:appveyorlabrepo\sql2008-backups\Noextension.bak -ErrorVariable Errvar -WarningVariable WarnVar
        It "Should Restore successfully" {
            ($results.RestoreComplete -contains $false) | Should Be $false
            (($results | Measure-Object).count -gt 0) | Should be $True
        }
    }
    Clear-DbaConnectionPool
    Start-Sleep -Seconds 1

    Context "All user databases are removed post history test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Context "Setup for Recovery Tests" {
        $DatabaseName = 'rectest'
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -NoRecovery -DatabaseName $DatabaseName -DestinationFilePrefix $DatabaseName -WithReplace
        It "Should have restored everything successfully" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | measure-Object).count -gt 0) | Should be $True
        }
        $check = Get-DbaDatabase -SqlInstance $script:instance2 -Database $DatabaseName
        It "Should return 1 database" {
            $check.count | Should Be 1
        }
        It "Should be a database in Restoring state" {
            $check.status | Should Be 'Restoring'
        }
    }

    Context "Test recovery via parameter" {
        $DatabaseName = 'rectest'
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Recover -DatabaseName $DatabaseName
        It "Should have restored everything successfully" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | measure-Object).count -gt 0) | Should be $True
        }
        $check = Get-DbaDatabase -SqlInstance $script:instance2 -Database $DatabaseName
        It "Should return 1 database" {
            $check.count | Should Be 1
        }
        It "Should be a database in Restoring state" {
            'Normal' -in $check.status | Should Be $True
        }
    }

    Context "Setup for Recovery Tests" {
        $DatabaseName = 'rectest'
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -NoRecovery -DatabaseName $DatabaseName -DestinationFilePrefix $DatabaseName -WithReplace
        It "Should have restored everything successfully" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | measure-Object).count -gt 0) | Should be $True
        }
        $check = Get-DbaDatabase -SqlInstance $script:instance2 -Database $DatabaseName
        It "Should return 1 database" {
            $check.count | Should Be 1
        }
        It "Should be a database in Restoring state" {
            $check.status | Should Be 'Restoring'
        }
    }

    Context "Test recovery via pipeline" {
        $DatabaseName = 'rectest'
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -Database $DatabaseName | Restore-DbaDatabase -SqlInstance $script:instance2 -Recover
        It "Should have restored everything successfully" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | measure-Object).count -gt 0) | Should be $True
        }
        $check = Get-DbaDatabase -SqlInstance $script:instance2 -Database $DatabaseName
        It "Should return 1 database" {
            $check.count | Should Be 1
        }
        It "Should be a database in Restoring state" {
            'Normal' -in $check.status | Should Be $True
        }
    }

    Context "Checking we cope with a port number (#244)" {
        $DatabaseName = 'rectest'
        $results = Restore-DbaDatabase -SqlInstance $script:instance2_detailed -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $DatabaseName -DestinationFilePrefix $DatabaseName -WithReplace
        It "Should have restored everything successfully" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | measure-Object).count -gt 0) | Should be $True
        }
    }

    Context "All user databases are removed post port test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Context "Checking OutputScriptOnly only outputs script" {
        $DatabaseName = 'rectestSO'
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $DatabaseName -OutputScriptOnly
        $db = Get-DbaDatabase -SqlInstance $script:instance2 -Database $DatabaseName
        It "Should only output a script" {
            $results -match 'RESTORE DATABASE' | Should be $True
            ($null -eq $db) | Should be $True
        }
    }
    Context "Checking OutputScriptOnly only outputs script without changing state for existing dbs (#2940)" {
        $DatabaseName = 'dbatoolsci_rectestSO'
        Get-DbaDatabase -SqlInstance $script:instance2 -Database $DatabaseName | Remove-DbaDatabase -Confirm:$false
        $server = Connect-DbaInstance $script:instance2
        $server.Query("CREATE DATABASE $DatabaseName")
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $DatabaseName -OutputScriptOnly -WithReplace
        $db = Get-DbaDatabase -SqlInstance $script:instance2 -Database $DatabaseName
        It "Should only output a script" {
            $results -match 'RESTORE DATABASE' | Should be $True
        }
        It "Doesn't change the status of the existing database" {
            $db.UserAccess | Should Be 'Multiple'
        }
        $db | Remove-DbaDatabase -Confirm:$false
    }
    Context "All user databases are removed post Output script test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }
    Context "Checking Output vs input" {
        $DatabaseName = 'rectestSO'
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $DatabaseName -BufferCount 24 -MaxTransferSize 128kb -BlockSize 64kb

        It "Should return the destination instance" {
            $results.SqlInstance = $script:instance2
        }

        It "Should have a BlockSize of 65536" {
            $results.Script | Should match 'BLOCKSIZE = 65536'
        }

        It "Should have a BufferCount of 24" {
            $results.Script | Should match 'BUFFERCOUNT = 24'
        }

        It "Should have a MaxTransferSize of 131072" {
            $results.Script | Should match 'MAXTRANSFERSIZE = 131072'
        }
    }

    Context "All user databases are removed post Output vs Input test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Context "Checking CDC parameter " {
        $output = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $DatabaseName -OutputScriptOnly -KeepCDC -WithReplace
        It "Should have KEEP_CDC in the SQL" {
            ($output -like '*KEEP_CDC*') | Should be $True
        }
        $output = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $DatabaseName -OutputScriptOnly -KeepCDC -WithReplace -WarningVariable warnvar -NoRecovery -WarningAction SilentlyContinue
        It "Should not output, and warn if Norecovery and KeepCDC specified" {
            ($warnvar -like '*KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work') | Should be $True
            $output | Should be $null
        }
        $output = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $DatabaseName -OutputScriptOnly -KeepCDC -WithReplace -WarningVariable warnvar -StandbyDirectory c:\temp\ -WarningAction SilentlyContinue
        It "Should not output, and warn if StandbyDirectory and KeepCDC specified" {
            ($warnvar -like '*KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work') | Should be $True
            $output | Should be $null
        }
    }

    Context "Page level restores" {
        Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName PageRestore -DestinationFilePrefix PageRestore
        $sql = "alter database PageRestore set Recovery Full
        Create table testpage(
            Filler char(8000)
        )

        insert into testpage values (REPLICATE('a','8000'))
        insert into testpage values (REPLICATE('b','8000'))
        insert into testpage values (REPLICATE('c','8000'))
        insert into testpage values (REPLICATE('d','8000'))

        Backup database PageRestore to disk='c:\temp\pagerestore.bak'
        Create table #TmpIndex(
        PageFiD int,
        PagePid int,
        IAMFID int,
        IAMPid int,
        ObjectID int,
        IndexID int,
        PartitionNumber bigint,
        ParitionId bigint,
        iam_chain_type varchar(50),
        PageType int,
        IndexLevel int,
        NextPageFID int,
        NextPagePID int,
        prevPageFid int,
        PrevPagePID int
        )

        insert #TmpIndex exec ('dbcc ind(PageRestore,testpage,-1)')
        dbcc ind(PageRestore,testpage,-1)

        declare @pageid int
        select top 1 @pageid=PagePid from #TmpIndex where IAMFID is not null and IAmPID is not null

        --select * from #TmpIndex
        --pageid = 256
        alter database pagerestore set single_user with rollback immediate

        dbcc writepage(pagerestore,1,@pageid,0,1,0x41,1)
        dbcc writepage(pagerestore,1,@pageid,1,1,0x41,1)
        dbcc writepage(pagerestore,1,@pageid,2,1,0x41,1)

        alter database pagerestore set multi_user

        insert into testpage values (REPLICATE('e','8000'))

        Backup log PageRestore to disk='c:\temp\PageRestore.trn'

        insert into testpage values (REPLICATE('f','8000'))
        use master"
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query $sql -Database Pagerestore
        $sqlResults2 = Invoke-DbaQuery -SqlInstance $script:instance2 -Database Master -Query "select * from pagerestore.dbo.testpage where filler like 'a%'" -ErrorVariable errvar -ErrorAction SilentlyContinue
        It "Should have warned about corruption" {
            ($errvar -match "SQL Server detected a logical consistency-based I/O error: incorrect checksum \(expected") | Should be $True
            ($null -eq $sqlResults2) | SHould be $True
        }
        $null = Get-DbaDbBackupHistory -SqlInstance $script:instance2 -Database pagerestore -last | Restore-DbaDatabase -SqlInstance $script:instance2 -PageRestore (Get-DbaSuspectPage -SqlInstance $script:instance2 -Database PageRestore) -TrustDbBackupHistory -DatabaseName PageRestore -PageRestoreTailFolder c:\temp -ErrorAction SilentlyContinue
        $sqlResults3 = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "select * from pagerestore.dbo.testpage where filler like 'f%'" -ErrorVariable errvar3 -ErrorAction SilentlyContinue
        It -Skip "Should work after page restore" {
            #($null -eq $errvar3) | Should Be $True
            ($null -eq $sqlResults3) | SHould be $False
        }


    }

    Context "Testing Backup to Restore piping" {
        Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName PipeTest -DestinationFilePrefix PipeTest
        $results = Backup-DbaDatabase -SqlInstance $script:instance2 -Database Pipetest -BackupDirectory c:\temp -CopyOnly -WarningAction SilentlyContinue -WarningVariable bwarnvar -ErrorAction SilentlyContinue -ErrorVariable berrvar | Restore-DbaDatabase -SqlInstance $script:instance2 -DatabaseName restored -ReplaceDbNameInFile -WarningAction SilentlyContinue -WarningVariable rwarnvar -ErrorAction SilentlyContinue -ErrorVariable rerrvar
        It "Should backup and restore cleanly" {
            $results.RestoreComplete | Should Be $True
        }
    }

    Context "Check we restore striped database" {
        Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\sql2008-backups\RestoreTimeStripe -DatabaseName StripeTest -DestinationFilePrefix StripeTest
        It "Should backup and restore cleanly" {
            ($results | Where-Object { $_.RestoreComplete -eq $True }).count | Should Be $Results.count
        }
    }

    Context "Don't try to create/test folders with OutputScriptOnly (Issue 4046)" {
        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\RestoreTimeClean2016\RestoreTimeClean.bak -DestinationDataDirectory g:\DoesNtExist -OutputScriptOnly -WarningVariable warnvar
        It "Should not raise a warning" {
            ('' -eq $warnvar) | Should -Be $True
        }
    }
    Context "Checking that WITH KEEP_REPLICATION gets properly added" {
        $DatabaseName = 'reptestSO'
        $results = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $DatabaseName -OutputScriptOnly -KeepReplication
        It "Should output a script with keep replication clause" {
            $results -match 'RESTORE DATABASE.*WITH.*KEEP_REPLICATION' | Should be $True
        }
    }

    Context "Test restoring a Backup encrypted with Certificate" {
        New-DbaDatabase -SqlInstance $script:instance2 -Name EncRestTest -Confirm:$false
        $securePass = ConvertTo-SecureString "estBackupDir\master\script:instance1).split('\')[1])\Full\master-Full.bak" -AsPlainText -Force
        New-DbaDbMasterKey -SqlInstance $script:instance2 -Database Master -SecurePassword $securePass -confirm:$false
        $cert = New-DbaDbCertificate -SqlInstance $script:instance2 -Database Master -Name RestoreTestCert -Subject RestoreTestCert
        $encBackupResults = Backup-DbaDatabase -SqlInstance $script:instance2 -Database EncRestTest -EncryptionAlgorithm AES128 -EncryptionCertificate RestoreTestCert
        It "Should encrypt the backup" {
            $encBackupResults.EncryptorType | Should Be "CERTIFICATE"
            $encBackupResults.KeyAlgorithm | Should Be "aes_128"
        }
        $results = $encBackupResults | Restore-DbaDatabase -SqlInstance $script:instance2 -TrustDbBackupHistory -RestoredDatabaseNamePrefix cert -DestinationFilePrefix cert -confirm:$false
        It "Should have restored the backup" {
            $results.RestoreComplete | Should Be $True
        }
        Remove-DbaDbCertificate -SqlInstance $script:instance2 -Database Master -Certificate RestoreTestCert -Confirm:$false
        Remove-DbaDbMasterKey -SqlInstance $script:instance2 -Database Master -confirm:$false
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database EncRestTest -confirm:$false
    }

    if ($env:azurepasswd) {
        Context "Restores From Azure using SAS" {
            BeforeAll {
                $server = Connect-DbaInstance -SqlInstance $script:instance2
                if (Get-DbaCredential -SqlInstance $script:instance2 -Name "[$script:azureblob]" ) {
                    $sql = "DROP CREDENTIAL [$script:azureblob]"
                    $server.Query($sql)
                }
                $sql = "CREATE CREDENTIAL [$script:azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
                $server.Query($sql)
                $server.Query("CREATE DATABASE dbatoolsci_azure")
            }
            AfterAll {
                $server.Query("DROP CREDENTIAL [$script:azureblob]")
                Get-DbaDatabase -SqlInstance $script:instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase -Confirm:$false
            }
            It "Should restore cleanly" {
                $results = Restore-DbaDatabase -SqlInstance $script:instance2 -WithReplace -DatabaseName dbatoolsci_azure -Path $script:azureblob/dbatoolsci_azure.bak
                $results.BackupFile | Should -Be "$script:azureblob/dbatoolsci_azure.bak"
                $results.RestoreComplete | Should Be $True
            }
        }
    }

    if ($env:azurepasswd -and -not $env:appveyor) {
        Context "Restores Striped backup From Azure using SAS" {
            BeforeAll {
                $server = Connect-DbaInstance -SqlInstance $script:instance2
                if (Get-DbaCredential -SqlInstance $script:instance2 -name "[$script:azureblob]" ) {
                    $sql = "DROP CREDENTIAL [$script:azureblob]"
                    $server.Query($sql)
                }
                $sql = "CREATE CREDENTIAL [$script:azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
                $server.Query($sql)
                $server.Query("CREATE DATABASE dbatoolsci_azure")
            }
            AfterAll {
                $server.Query("DROP CREDENTIAL [$script:azureblob]")
                Get-DbaDatabase -SqlInstance $script:instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase -Confirm:$false
            }
            It "Should restore cleanly" {
                $results = @("$script:azureblob/az-1.bak", "$script:azureblob/az-2.bak", "$script:azureblob/az-3.bak") | Restore-DbaDatabase -SqlInstance $script:instance2 -DatabaseName azstripetest  -WithReplace -ReplaceDbNameInFile
                $results.RestoreComplete | Should Be $True
            }
        }
    }
    if ($env:azurelegacypasswd) {
        Context "Restores from Azure using Access Key" {
            BeforeAll {
                Get-DbaDatabase -SqlInstance $script:instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase -Confirm:$false
                $server = Connect-DbaInstance -SqlInstance $script:instance2
                if (Get-DbaCredential -SqlInstance $script:instance2 -name dbatools_ci) {
                    $sql = "DROP CREDENTIAL dbatools_ci"
                    $server.Query($sql)
                }
                $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$script:azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
                $server.Query($sql)
                $server.Query("CREATE DATABASE dbatoolsci_azure")
            }
            AfterAll {
                $server.Query("DROP CREDENTIAL dbatools_ci")
                Get-DbaDatabase -SqlInstance $script:instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase -Confirm:$false
            }
            It -Skip "supports legacy credential setups" {
                $results = Restore-DbaDatabase -SqlInstance $script:instance2 -WithReplace -DatabaseName dbatoolsci_azure -Path https://dbatools.blob.core.windows.net/legacy/dbatoolsci_azure.bak -AzureCredential dbatools_ci
                $results.BackupFile | Should -Be 'https://dbatools.blob.core.windows.net/legacy/dbatoolsci_azure.bak'
                $results.Script -match 'CREDENTIAL' | Should -Be $true
                $results.RestoreComplete | Should Be $True
            }
        }
    }
    #>
}
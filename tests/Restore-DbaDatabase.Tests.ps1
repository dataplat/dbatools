$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    #Setup variable for multiple contexts
    $DataFolder = 'c:\temp\datafiles'
    $LogFolder = 'C:\temp\logfiles'
    New-Item -Type Directory $DataFolder -ErrorAction SilentlyContinue
    New-Item -Type Directory $LogFolder -ErrorAction SilentlyContinue

    Context "Properly restores a database on the local drive using Path" {
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase -Confirm:$false
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak
        It "Should Return the proper backup file location" {
            $results.BackupFile | Should Be "$script:appveyorlabrepo\singlerestore\singlerestore.bak"
        }
        It "Should return successful restore" {
            $results.RestoreComplete | Should Be $true
        }
    }

    Context "Ensuring warning is thrown if database already exists" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -WarningVariable warning -WarningAction SilentlyContinue
        It "Should warn" {
            $warning | Where-Object {$_ -like '*Test-DbaBackupInformation*Database*'} | Should Match "exists and WithReplace not specified, stopping"
        }
        It "Should not return object" {
            $results | Should Be $null
        }
    }

    Context "Database is properly removed again after withreplace test" {
        Get-DbaProcess $script:instance1 -Database singlerestore | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database singlerestore
        Get-DbaProcess $script:instance1 -Database singlerestore | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status -eq "Dropped" -or $results.Status -eq $null
        }
    }

    Get-DbaProcess $script:instance1 -NoSystemSpid | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Context "Properly restores a database on the local drive using piped Get-ChildItem results" {
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance1
        It "Should Return the proper backup file location" {
            $results.BackupFile | Should Be "$script:appveyorlabrepo\singlerestore\singlerestore.bak"
        }
        It "Should return successful restore" {
            $results.RestoreComplete | Should Be $true
        }
    }

    Context "Test VerifyOnly works with db in existence" {
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance1  -VerifyOnly
        It "Should have verified Successfully" {
            $results[0] | Should Be "Verify successful"
        }
    }

    Get-DbaProcess $script:instance1 -NoSystemSpid | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Context "Database is properly removed again after gci tests" {
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }

    Get-DbaProcess $script:instance1 -NoSystemSpid | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 2

    Context "Database is restored with correct renamings" {
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance1 -DestinationFilePrefix prefix
        It "Should return successful restore with prefix" {
            $results.RestoreComplete | Should Be $true
        }
        It "Should return the 2 prefixed files" {
            (($results.RestoredFile -split ',').substring(0, 6) -eq 'prefix').count | Should be 2
        }
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance1 -DestinationFileSuffix suffix -WithReplace
        It "Should return successful restore with suffix" {
            ($results.RestoreComplete -eq $true) | Should Be $true
        }
        It "Should return the 2 suffixed files" {
            (($Results.RestoredFile -split ',') -match "suffix\.").count | Should be 2
        }
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance1 -DestinationFileSuffix suffix -DestinationFilePrefix prefix -WithReplace
        It "Should return successful restore with suffix and prefix" {
            ($results.RestoreComplete -eq $true)  | Should Be $true
        }
        It "Should return the 2 prefixed and suffixed files" {
            (($Results.RestoredFile -split ',') -match "^prefix.*suffix\.").count | Should be 2
        }
    }

    Get-DbaProcess $script:instance1 -NoSystemSpid | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Context "Database is properly removed again post prefix and suffix tests" {
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }

    }

    Context "Replace databasename in Restored File" {
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance1 -DatabaseName Pestering -replaceDbNameInFile -WithReplace
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
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database pestering
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }

    Get-DbaProcess $script:instance1 -NoSystemSpid | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 2

    Context "Folder restore options" {
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance1 -DestinationDataDirectory $DataFolder
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

        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance1 -DestinationDataDirectory $DataFolder -DestinationLogDirectory $LogFolder -WithReplace
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
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }

    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 2
    Context "Putting all restore file modification options together" {
        $results = Get-ChildItem $script:appveyorlabrepo\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance $script:instance1 -DestinationDataDirectory $DataFolder -DestinationLogDirectory $LogFolder -DestinationFileSuffix Suffix -DestinationFilePrefix prefix
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

    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 1
    Context "Database is properly removed again after all file mods test" {
        $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }

    Get-DbaProcess $script:instance1 -NoSystemSpid | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 5
    Clear-DbaSqlConnectionPool

    Context "Properly restores an instance using ola-style backups via pipe" {
        $results = Get-ChildItem $script:appveyorlabrepo\sql2008-backups | Restore-DbaDatabase -SqlInstance $script:instance1
        It "Restored files count should be the right number" {
            $results.DatabaseName.Count | Should Be 28
        }
        It "Should return successful restore" {
            ($results.RestoreComplete -contains $false) | Should Be $false
            ($results.count -gt 0) | Should be $True
        }
    }

    Context "Database is properly removed again after ola pipe test" {
        Get-DbaProcess $script:instance1 -NoSystemSpid | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -ExcludeAllSystemDb | Remove-DbaDatabase -Confirm:$false
        Get-DbaProcess $script:instance1 -NoSystemSpid | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -ExcludeAllSystemDb | Remove-DbaDatabase -Confirm:$false

        It "Should say the status was dropped or null" {
            foreach ($result in $results) {
                $result.Status -eq "Dropped" -or $result.Status -eq $null
            }
        }
    }

    Context "Properly restores an instance using ola-style backups via string" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\sql2008-backups
        It "Restored files count should be the right number" {
            $results.DatabaseName.Count | Should Be 28
        }
        It "Should return successful restore" {
            ($results.RestoreComplete -contains $false) | Should Be $false
            ($results.count -gt 0) | Should be $True
        }
    }

    Get-DbaProcess $script:instance1 -NoSystemSpid | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue

    Context "All user databases are removed post ola-style test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase -Confirm:$false
        It -Skip "Should say the status was dropped" {
            $results | ForEach-Object { $_.Status | Should Be "Dropped" }
        }
    }

    Get-DbaProcess $script:instance1 -NoSystemSpid | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 2

    Context "RestoreTime setup checks" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -path $script:appveyorlabrepo\RestoreTimeClean
        $sqlResults = Invoke-Sqlcmd2 -ServerInstance $script:instance1 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
        It "Should restore cleanly" {
            ($results.RestoreComplete -contains $false) | Should Be $false
            ($results.count -gt 0) | Should be $True
        }
        It "Should have restored 5 files" {
            $results.count | Should be 5
        }
        It "Should have restored from 2017-06-01 12:59:12" {
            $sqlResults.mindt | Should be (get-date "2017-06-01 12:59:12")
        }
        It "Should have restored to 2017-06-01 13:28:43" {
            $sqlResults.maxdt | Should be (get-date "2017-06-01 13:28:43")
        }
    }

    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 1

    Context "All user databases are removed post RestoreTime check" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 1

    Context "RestoreTime point in time" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -path $script:appveyorlabrepo\RestoreTimeClean -RestoreTime (get-date "2017-06-01 13:22:44")
        $sqlResults = Invoke-Sqlcmd2 -ServerInstance $script:instance1 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
        It "Should have restored 4 files" {
            $results.count | Should be 4
        }
        It "Should have restored from 2017-06-01 12:59:12" {
            $sqlResults.mindt | Should be (get-date "2017-06-01 12:59:12")
        }
        It "Should have restored to 2017-06-01 13:28:43" {
            $sqlResults.maxdt | Should be (get-date "2017-06-01 13:22:43")
        }
    }

    Context "All user databases are removed" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase -Confirm:$false
        It -Skip "Should say the status was dropped post point in time test" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 1

    Context "RestoreTime point in time with Simple Model" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -path $script:appveyorlabrepo\sql2008-backups\SimpleRecovery\ -RestoreTime (get-date "2018-04-06 10:37:44")
        $sqlResults = Invoke-Sqlcmd2 -ServerInstance $script:instance1 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from SimpleBackTest.dbo.steps"
        
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
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped post point in time test" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 1

    Context "RestoreTime point in time and continue" {
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase -Confirm:$false
        }
        $Should_Run = (Connect-DbaInstance -SqlInstance $script:instance1).Version.ToString() -like '10.50*'
        if (-not($Should_Run)) {
            It "The test can run" {
                Set-TestInconclusive -Message "a 2008R2 is strictly needed"
            }
            return
        }
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -path $script:appveyorlabrepo\RestoreTimeClean -RestoreTime (get-date "2017-06-01 13:22:44") -StandbyDirectory c:\temp
        $sqlResults = Invoke-Sqlcmd2 -ServerInstance $script:instance1 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
        It "Should have restored 4 files" {
            $results.count | Should be 4
        }
        It "Should have restored from 2017-06-01 12:59:12" {
            $sqlResults.mindt | Should be (get-date "2017-06-01 12:59:12")
        }
        It "Should have restored to 2017-06-01 13:22:43" {
            $sqlResults.maxdt | Should be (get-date "2017-06-01 13:22:43")
        }
        $results2 = Restore-DbaDatabase -SqlInstance $script:instance1 -path $script:appveyorlabrepo\RestoreTimeClean -Continue
        $sqlResults2 = Invoke-Sqlcmd2 -ServerInstance $script:instance1 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
        It "Should have restored 2 files" {
            $results2.count | Should be 2
        }
        It "Should have restored from 2017-06-01 12:59:12" {
            $sqlResults2.mindt | Should be (get-date "2017-06-01 12:59:12")
        }
        It "Should have restored to 2017-06-01 13:28:43" {
            $sqlResults2.maxdt | Should be (get-date "2017-06-01 13:28:43")
        }

    }

    Context "Backup DB For next test" {
        $null = Restore-DbaDatabase -SqlInstance $script:instance1 -path $script:appveyorlabrepo\RestoreTimeClean -RestoreTime (get-date "2017-06-01 13:22:44")
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database RestoreTimeClean -BackupDirectory C:\temp
        It "Should return successful backup" {
            $results.BackupComplete | Should Be $true
        }
    }

    Context "All user databases are removed post continue test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 1

    Get-DbaProcess $script:instance1 | Where-Object Program -match 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
    Context "Check Get-DbaBackupHistory pipes into Restore-DbaDatabase" {
        $history = Get-DbaBackupHistory -SqlInstance $script:instance1 -Database RestoreTimeClean -Last
        $results = $history | Restore-DbaDatabase -SqlInstance $script:instance1 -WithReplace -TrustDbBackupHistory
        It "Should have restored everything successfully" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | Measure-Object).count -gt 0) | Should be $True
        }
    }

    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 1

    Context "All user databases are removed post history test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Context "Restores a db with log and file files missing extensions" {
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -path $script:appveyorlabrepo\sql2008-backups\Noextension.bak -ErrorVariable Errvar -WarningVariable WarnVar
        It "Should Restore successfully" {
            ($results.RestoreComplete -contains $false) | Should Be $false
            (($results | Measure-Object).count -gt 0) | Should be $True
        }
    }
    Clear-DbaSqlConnectionPool
    Start-Sleep -Seconds 1

    Context "All user databases are removed post history test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Context "Setup for Recovery Tests" {
        $DatabaseName = 'rectest'
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -NoRecovery -DatabaseName $DatabaseName -DestinationFilePrefix $DatabaseName -WithReplace
        It "Should have restored everything successfully" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | measure-Object).count -gt 0) | Should be $True
        }
        $check = Get-DbaDatabase -SqlInstance $script:instance1 -Database $DatabaseName
        It "Should return 1 database" {
            $check.count | Should Be 1
        }
        It "Should be a database in Restoring state" {
            $check.status | Should Be 'Restoring'
        }
    }

    Context "Test recovery via parameter" {
        $DatabaseName = 'rectest'
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -Recover -DatabaseName $DatabaseName
        It "Should have restored everything successfully" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | measure-Object).count -gt 0) | Should be $True
        }
        $check = Get-DbaDatabase -SqlInstance $script:instance1 -Database $DatabaseName
        It "Should return 1 database" {
            $check.count | Should Be 1
        }
        It "Should be a database in Restoring state" {
            'Normal' -in $check.status | Should Be $True
        }
    }

    Context "Setup for Recovery Tests" {
        $DatabaseName = 'rectest'
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -NoRecovery -DatabaseName $DatabaseName -DestinationFilePrefix $DatabaseName -WithReplace
        It "Should have restored everything successfully" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | measure-Object).count -gt 0) | Should be $True
        }
        $check = Get-DbaDatabase -SqlInstance $script:instance1 -Database $DatabaseName
        It "Should return 1 database" {
            $check.count | Should Be 1
        }
        It "Should be a database in Restoring state" {
            $check.status | Should Be 'Restoring'
        }
    }

    Context "Test recovery via pipeline" {
        $DatabaseName = 'rectest'
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -Database $DatabaseName | Restore-DbaDatabase -SqlInstance $script:instance1 -Recover
        It "Should have restored everything successfully" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | measure-Object).count -gt 0) | Should be $True
        }
        $check = Get-DbaDatabase -SqlInstance $script:instance1 -Database $DatabaseName
        It "Should return 1 database" {
            $check.count | Should Be 1
        }
        It "Should be a database in Restoring state" {
            'Normal' -in $check.status | Should Be $True
        }
    }

    Context "Checking we cope with a port number (#244)" {
        $DatabaseName = 'rectest'
        $results = Restore-DbaDatabase -SqlInstance $script:instance1_detailed -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak  -DatabaseName $DatabaseName -DestinationFilePrefix $DatabaseName -WithReplace
        It "Should have restored everything successfully" {
            ($results.RestoreComplete -contains $false) | Should be $False
            (($results | measure-Object).count -gt 0) | Should be $True
        }
    }

    Context "All user databases are removed post port test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Context "Checking OutputScriptOnly only outputs script" {
        $DatabaseName = 'rectestSO'
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak  -DatabaseName $DatabaseName -OutputScriptOnly
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $DatabaseName
        It "Should only output a script" {
            $results -match 'RESTORE DATABASE' | Should be $True
            ($null -eq $db) | Should be $True
        }
    }
    Context "Checking OutputScriptOnly only outputs script without changing state for existing dbs (#2940)" {
        $DatabaseName = 'dbatoolsci_rectestSO'
        Get-DbaDatabase -SqlInstance $script:instance1 -Database $DatabaseName | Remove-DbaDatabase -Confirm:$false
        $server = Connect-DbaInstance $script:instance1
        $server.Query("CREATE DATABASE $DatabaseName")
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $DatabaseName -OutputScriptOnly -WithReplace
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $DatabaseName
        It "Should only output a script" {
            $results -match 'RESTORE DATABASE' | Should be $True
        }
        It "Doesn't change the status of the existing database" {
            $db.UserAccess | Should Be 'Multiple'
        }
        $db | Remove-DbaDatabase -Confirm:$false
    }
    Context "All user databases are removed post Output script test" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }
    Context "Checking Output vs input" {
        $DatabaseName = 'rectestSO'
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak  -DatabaseName $DatabaseName -BufferCount 24 -MaxTransferSize 128kb -BlockSize 64kb

        It "Should return the destination instance" {
            $results.SqlInstance = $script:instance1
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
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase -Confirm:$false
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Context "Checking CDC parameter " {
        $output = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak  -DatabaseName $DatabaseName -OutputScriptOnly -KeepCDC -WithReplace
        It "Should have KEEP_CDC in the SQL" {
            ($output -like '*KEEP_CDC*') | Should be $True
        }
        $output = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak  -DatabaseName $DatabaseName -OutputScriptOnly -KeepCDC -WithReplace -WarningVariable warnvar -NoRecovery -WarningAction SilentlyContinue
        It "Should not output, and warn if Norecovery and KeepCDC specified" {
            ( $warnvar -like '*KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work') | Should be $True
            $output | Should be $null
        }
        $output = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak  -DatabaseName $DatabaseName -OutputScriptOnly -KeepCDC -WithReplace -WarningVariable warnvar -StandbyDirectory c:\temp\ -WarningAction SilentlyContinue
        It "Should not output, and warn if StandbyDirectory and KeepCDC specified" {
            ( $warnvar -like '*KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work') | Should be $True
            $output | Should be $null
        }
    }

    Context "Page level restores" {
        Get-DbaDatabase -SqlInstance $script:instance1 -ExcludeAllSystemDb | Remove-DbaDatabase -confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName PageRestore -DestinationFilePrefix PageRestore
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
        $null = Invoke-Sqlcmd2 -ServerInstance $script:instance1 -Query $sql -Database Pagerestore
        $sqlResults2 = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database Master -Query "select * from pagerestore.dbo.testpage where filler like 'a%'" -ErrorVariable errvar -ErrorAction SilentlyContinue
        It "Should have warned about corruption" {
            ($errvar -match "SQL Server detected a logical consistency-based I/O error: incorrect checksum \(expected") | Should be $True
            ($null -eq $sqlResults2) | SHould be $True
        }
        $null = Get-DbaBackupHistory -SqlInstance $script:instance1 -Database pagerestore -last  | Restore-DbaDatabase -SqlInstance $script:instance1 -PageRestore (Get-DbaSuspectPage -SqlInstance $script:instance1 -Database PageRestore) -TrustDbBackupHistory -AllowContinue -DatabaseName PageRestore -PageRestoreTailFolder c:\temp -ErrorAction SilentlyContinue
        $sqlResults3 = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Query "select * from pagerestore.dbo.testpage where filler like 'f%'" -ErrorVariable errvar3 -ErrorAction SilentlyContinue
        It "Should work after page restore" {
            #($null -eq $errvar3) | Should Be $True
            ($null -eq $sqlResults3) | SHould be $False
        }


    }

    Context "Testing Backup to Restore piping" {
        Get-DbaDatabase -SqlInstance $script:instance1 -ExcludeAllSystemDb | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName PipeTest -DestinationFilePrefix PipeTest
        $results = Backup-DbaDatabase -SqlInstance $script:instance1 -Database Pipetest -BackupDirectory c:\temp -CopyOnly -WarningAction SilentlyContinue -WarningVariable bwarnvar -ErrorAction SilentlyContinue -ErrorVariable berrvar | Restore-DbaDatabase -SqlInstance $script:instance1 -DatabaseName restored -ReplaceDbNameInFile -WarningAction SilentlyContinue -WarningVariable rwarnvar -ErrorAction SilentlyContinue -ErrorVariable rerrvar
        It "Should backup and restore cleanly" {
            $results.RestoreComplete | Should Be $True
        }
    }

    Context "Check we restore striped database" {
        Get-DbaDatabase -SqlInstance $script:instance1 -ExcludeAllSystemDb | Remove-DbaDatabase -Confirm:$false
        $results = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\sql2008-backups\RestoreTimeStripe -DatabaseName StripeTest -DestinationFilePrefix StripeTest
        It "Should backup and restore cleanly" {
            ($results | Where-Object {$_.RestoreComplete -eq $True}).count | Should Be $Results.count
        }
    }
}
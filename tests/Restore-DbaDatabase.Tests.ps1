Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
Describe "Restore-DbaDatabase Integration Tests" -Tags "Integrationtests" {
    #Setup variable for multuple contexts
    $DataFolder = 'c:\temp\datafiles'
    $LogFolder = 'C:\temp\logfiles'
    New-Item -Type Directory $DataFolder -ErrorAction SilentlyContinue
    new-Item -Type Directory $LogFolder -ErrorAction SilentlyContinue
    Context "Properly restores a database on the local drive using Path" {
        $null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
        $results = Restore-DbaDatabase -SqlInstance localhost -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak
        It "Should Return the proper backup file location" {
            $results.BackupFile | Should Be "C:\github\appveyor-lab\singlerestore\singlerestore.bak"
        }
        It "Should return successful restore" {
            $results.RestoreComplete | Should Be $true
        }
    }
	
    Context "Ensuring warning is thrown if database already exists" {
        $results = Restore-DbaDatabase -SqlInstance localhost -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak -WarningVariable warning
        It "Should warn" {
            $warning | Should Match "exists and WithReplace not specified, stopping"
        }
        It "Should not return object" {
            $results | Should Be $null
        }
    }
	
    Context "Database is properly removed again after withreplace test" {
        $results = Remove-DbaDatabase -SqlInstance localhost -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }

    Context "Properly restores a database on the local drive using piped Get-ChildItem results" {
        $results = Get-ChildItem C:\github\appveyor-lab\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance localhost
        It "Should Return the proper backup file location" {
            $results.BackupFile | Should Be "C:\github\appveyor-lab\singlerestore\singlerestore.bak"
        }
        It "Should return successful restore" {
            $results.RestoreComplete | Should Be $true
        }
    }
  
    Context "Database is properly removed again after gci tests" {
        $results = Remove-DbaDatabase -SqlInstance localhost -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }
	
    Context "Database is restored with correct renamings" {
        $results = Get-ChildItem C:\github\appveyor-lab\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance localhost -DestinationFilePrefix prefix
        It "Should return successful restore with prefix" {
            $results.RestoreComplete | Should Be $true
        }
        It "Should return the 2 prefixed files" {
            (($results.RestoredFile -split ',').substring(0, 6) -eq 'prefix').count | Should be 2
        }
        $results = Get-ChildItem C:\github\appveyor-lab\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance localhost -DestinationFileSuffix suffix -WithReplace
        It "Should return successful restore with suffix" {
            $results.RestoreComplete | Should Be $true
        }
        It "Should return the 2 suffixed files" {
            (($Results.RestoredFile -split ',') -match "suffix\.").count | Should be 2
        }
        $results = Get-ChildItem C:\github\appveyor-lab\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance localhost -DestinationFileSuffix suffix -DestinationFilePrefix prefix -WithReplace
        It "Should return successful restore with suffix and prefix" {
            $results.RestoreComplete | Should Be $true
        }
        It "Should return the 2 prefixed and suffixed files" {
            (($Results.RestoredFile -split ',') -match "^prefix.*suffix\.").count | Should be 2
        }
    }
  
    Context "Database is properly removed again post prefix and suffix tests" {
        $results = Remove-DbaDatabase -SqlInstance localhost -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }

    }
	
	Context "Replace databasename in Restored File" {
        $results = Get-ChildItem C:\github\appveyor-lab\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance localhost -DatabaseName Pestering -replaceDbNameInFile -WithReplace
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
        $results = Remove-DbaDatabase -SqlInstance localhost -Database pestering
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }
	
    Context "Folder restore options" {
        $results = Get-ChildItem C:\github\appveyor-lab\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance localhost -DestinationDataDirectory $DataFolder
        It "Should return successful restore with DestinationDataDirectory" {
            $results.RestoreComplete | Should Be $true
        }
        It "Should have moved all files to $DataFolder" {
            (($results.restoredfilefull -split ',') -like "$DataFolder*").count | Should be 2
        }
        ForEach ($file in ($results.RestoredFileFull -split ',')) {
            It "$file Should exist on Filesystem" {
                $file | Should Exist	
            }
        }
        $results = Get-ChildItem C:\github\appveyor-lab\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance localhost -DestinationDataDirectory $DataFolder -DestinationLogDirectory $LogFolder -WithReplace
        It "Should have moved data file to $DataFolder" {
            (($results.restoredfilefull -split ',') -like "$DataFolder*").count | Should be 1
        }
        It "Should have moved Log file to $LogFolder" {
            (($results.restoredfilefull -split ',') -like "$LogFolder*").count | Should be 1
        }
        ForEach ($file in ($results.RestoredFileFull -split ',')) {
            It "$file Should exist on Filesystem" {
                $file | Should Exist	
            }
        }
    }

    Context "Database is properly removed again after folder options tests" {
        $results = Remove-DbaDatabase -SqlInstance localhost -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }

    Context "Putting all restore file modification options together" {
        $results = Get-ChildItem C:\github\appveyor-lab\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance localhost -DestinationDataDirectory $DataFolder -DestinationLogDirectory $LogFolder -DestinationFileSuffix Suffix -DestinationFilePrefix prefix
        It "Should return successful restore with all file mod options" {
            $results.RestoreComplete | Should Be $true
        }
        It "Should have moved data file to $DataFolder (output)" {
            (($results.restoredfilefull -split ',') -like "$DataFolder*").count | Should be 1
        }
        It "Should have moved Log file to $LogFolder (output)" {
            (($results.restoredfilefull -split ',') -like "$LogFolder*").count | Should be 1
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

    Context "Database is properly removed again after all file mods test" {
        $results = Remove-DbaDatabase -SqlInstance localhost -Database singlerestore
        It "Should say the status was dropped" {
            $results.Status | Should Be "Dropped"
        }
    }

    Context "Properly restores an instance using ola-style backups" {
        $results = Get-ChildItem C:\github\appveyor-lab\sql2008-backups | Restore-DbaDatabase -SqlInstance localhost
        It "Restored files count should be right" {
            $results.databasename.count | Should Be 30
        }
        It "Should return successful restore" {
            ($results.Restorecomplete -contains $false) | Should Be $false
        }
    }

    Context "All user databases are removed post ola-style test" {
        $results = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
        It "Should say the status was dropped" {
            $results.ForEach{ $_.Status | Should Be "Dropped" }
        }
    }

    Context "RestoreTime setup checks" {
        $results = Restore-DbaDatabase -SqlInstance localhost -path c:\github\appveyor-lab\RestoreTimeClean
        $sqlresults = Invoke-DbaSqlCmd -ServerInstance localhost -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
        It "Should restore cleanly" {
            ($results.RestoreComplete -contains $false) | Should Be $false
        }      
        It "Should have restored 5 files" {
            $results.count | Should be 5
        }
        It "Should have restored from 2017-06-01 12:59:12" {
            $sqlresults.mindt | Should be (get-date "2017-06-01 12:59:12")
        }
        It "Should have restored to 2017-06-01 13:28:43" {
            $sqlresults.maxdt | Should be (get-date "2017-06-01 13:28:43")
        }
    }

    Context "All user databases are removed post RestoreTime check" {
        $results = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Context "RestoreTime point in time" {
        $results = Restore-DbaDatabase -SqlInstance localhost -path c:\github\appveyor-lab\RestoreTimeClean -RestoreTime (get-date "2017-06-01 13:22:44")
        $sqlresults = Invoke-DbaSqlCmd -ServerInstance localhost -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
        It "Should have restored 4 files" {
            $results.count | Should be 4
        }
        It "Should have restored from 2017-06-01 12:59:12" {
            $sqlresults.mindt | Should be (get-date "2017-06-01 12:59:12")
        }
        It "Should have restored to 2017-06-01 13:28:43" {
            $sqlresults.maxdt | Should be (get-date "2017-06-01 13:22:43")
        }
    }

    Context "All user databases are removed" {
        $results = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
        It "Should say the status was dropped post point in time test" {
            Foreach ($db in $results){ $db.Status | Should Be "Dropped" }
        }
    }

    Context "RestoreTime point in time and continue" {
        $results = Restore-DbaDatabase -SqlInstance localhost -path c:\github\appveyor-lab\RestoreTimeClean -RestoreTime (get-date "2017-06-01 13:22:44") -StandbyDirectory c:\temp
        $sqlresults = Invoke-DbaSqlCmd -ServerInstance localhost -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
        It "Should have restored 4 files" {
            $results.count | Should be 4
        }
        It "Should have restored from 2017-06-01 12:59:12" {
            $sqlresults.mindt | Should be (get-date "2017-06-01 12:59:12")
        }
        It "Should have restored to 2017-06-01 13:22:43" {
            $sqlresults.maxdt | Should be (get-date "2017-06-01 13:22:43")
        }
        $results2 = Restore-DbaDatabase -SqlInstance localhost -path c:\github\appveyor-lab\RestoreTimeClean -Continue
        $sqlresults2 = Invoke-DbaSqlCmd -ServerInstance localhost -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
        It "Should have restored 2 files" {
            $results2.count | Should be 2
        }
        It "Should have restored from 2017-06-01 12:59:12" {
            $sqlresults2.mindt | Should be (get-date "2017-06-01 12:59:12")
        }
        It "Should have restored to 2017-06-01 13:28:43" {
            $sqlresults2.maxdt | Should be (get-date "2017-06-01 13:28:43")
        }

    }

    Context "Backup DB For next test" {
        $results = Backup-DbaDatabase -SqlInstance localhost -Database RestoreTimeClean -BackupDirectory C:\temp\backups
        It "Should return successful backup" {
			$results.BackupComplete | Should Be $true
		}
    }

    Context "All user databases are removed post continue test" {
        $results = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }

    Context "Check Get-DbaBackupHistory pipes into Restore-DbaDatabase" {
        $history = Get-DbaBackupHistory -SqlInstance localhost -Database RestoreTimeClean -Last
        $results = $history | Restore-DbaDatabase -SqlInstance localhost -WithReplace -TrustDbBackupHistory
        It "Should have restored everything successfully" {
            ($results.RestorComplete -contains $false) | Should be $False
        }
    }

    Context "All user databases are removed post history test" {
        $results = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
        It "Should say the status was dropped" {
            Foreach ($db in $results) { $db.Status | Should Be "Dropped" }
        }
    }
}
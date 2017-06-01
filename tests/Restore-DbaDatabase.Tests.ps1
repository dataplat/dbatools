#Setup variable for multuple contexts
$DataFolder = 'c:\temp\datafiles'
$LogFolder = 'C:\temp\logfiles'
New-Item -Type Directory $DataFolder
new-Item -Type Directory $LogFolder

Describe "Restore-DbaDatabase Integration Tests" -Tags "Integrationtests" {
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
            $warning | Should Match "exists and will not be overwritten"
        }
        It "Should not return object" {
            $results | Should Be $null
        }
    }
	
    Context "Database is properly removed for next test" {
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
  
    Context "Database is properly removed again" {
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
        $results = Get-ChildItem C:\github\appveyor-lab\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlInstance localhost -DatabaseName Pestering -replaceDbNameInFile -WithReplace
        It "Should return the 2 prefixed and suffixed files (output)" {
            (($Results.RestoredFile -split ',') -like "*pestering*").count | Should be 2
        }
        ForEach ($file in ($results.RestoredFileFull -split ',')) {
			It "$file Should exist on Filesystem" {
				$file | Should Exist	
			}
		}
    }

    Context "Database is properly removed again" {
        $results = Remove-DbaDatabase -SqlInstance localhost -Database singlerestore
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

	Context "Database is properly removed again" {
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

	Context "Database is properly removed again" {
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

	Context "All user databases are removed" {
		$results = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
		It "Should say the status was dropped" {
			$results.ForEach{ $_.Status | Should Be "Dropped" }
		}
	}
}
Describe "Backup-DbaDatabase Integration Tests" -Tags "Integrationtests" {
	Context "Properly restores a database on the local drive using Path" {
		$results = Backup-DbaDatabase -SqlInstance localhost -BackupDirectory C:\temp\backups
		It "Should return a database name, specifically master" {
			($results.DatabaseName -contains 'master') | Should Be $true
		}
		It "Should return successful restore" {
			$results.ForEach{ $_.BackupComplete | Should Be $true }
		}
	}
	
	Context "Should not backup if database and exclude match" {
		$results = Backup-DbaDatabase -SqlInstance localhost -BackupDirectory C:\temp\backups -Database master -Exclude master
		It "Should not return object" {
			$results | Should Be $null
		}
	}
	
	Context "Database should backup 1 database" {
		$results = Backup-DbaDatabase -SqlInstance localhost -BackupDirectory C:\temp\backups -Database master
		It "Database backup object count should be 1" {
			$results.DatabaseName.Count | Should Be 1
		}
	}
	
	Context "Database should backup 2 databases" {
		$results = Backup-DbaDatabase -SqlInstance localhost -BackupDirectory C:\temp\backups -Database master, msdb
		It "Database backup object count should be 2" {
			$results.DatabaseName.Count  | Should Be 2
		}
	}
	
	Context "Backup can pipe to restore" {
		$null = Restore-DbaDatabase -SqlServer localhost -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak
		$results = Backup-DbaDatabase -SqlInstance localhost -BackupDirectory C:\temp\backups -Database singlerestore | Restore-DbaDatabase -SqlInstance localhost\sql2016
		
		It "Should return successful restore" {
			$results.RestoreComplete | Should Be $true
		}
	}	
}
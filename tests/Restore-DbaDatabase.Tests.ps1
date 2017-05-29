Describe "Restore-DbaDatabase Integration Tests" -Tags "Integrationtests" {
	Context "Properly restores a database on the local drive using Path" {
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
	
}
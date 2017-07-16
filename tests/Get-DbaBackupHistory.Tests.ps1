Describe "Get-DbaBackupHistory Integration Tests" -Tags "Integrationtests" {
	
	Context "Setup removes, restores and backups on the local drive for Get-DbaBackupHistory" {
		$null = Restore-DbaDatabase -SqlInstance localhost -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak -WithReplace
		$db = Get-DbaDatabase -SqlInstance localhost -Database singlerestore
		$db | Backup-DbaDatabase -Type Full
		$db | Backup-DbaDatabase -Type Differential
		$db | Backup-DbaDatabase -Type Log
		$db | Backup-DbaDatabase -Type Log
		$null = Get-DbaDatabase -SqlInstance localhost -Database master | Backup-DbaDatabase -Type Full
	}
	
	<#
	Context "Get last history for single database" {
		$results = Get-DbaBackupHistory -SqlInstance localhost -Database singlerestore -Last
		It "Should be more than one database" {
			$results.count | Should Be 4
		}
	}
	#>
	
	Context "Get last history for all databases" {
		$results = Get-DbaBackupHistory -SqlInstance localhost
		It "Should be more than one database" {
			($results | Where-Object Database -match "master").Count | Should BeGreaterThan 0
		}
	}
}
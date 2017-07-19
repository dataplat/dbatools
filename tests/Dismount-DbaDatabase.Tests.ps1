Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
Describe "Dismount-DbaDatabase Integration Tests" -Tags "Integrationtests" {
	$dbname = "singlerestore"
	$null = Get-DbaDatabase -SqlInstance localhost -Database $dbname | Remove-DbaDatabase
	
	Context "Setup removes, restores and backups on the local drive for Dismount-DbaDatabase" {
		$null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
		$null = Restore-DbaDatabase -SqlInstance localhost -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak -DatabaseName $dbname -DestinationFilePrefix $dbname -WithReplace
		$null = Get-DbaDatabase -SqlInstance localhost -Database $dbname | Backup-DbaDatabase
	}
	
	Context "Detaches a single database and tests to ensure the alias still exists" {
		$results = Detach-DbaDatabase -SqlInstance localhost -Database $dbname -Force
		
		It "Should return success" {
			$results.DetachResult | Should Be "Success"
		}
		
		It "Should return that the database is only Database" {
			$results.Database | Should Be $dbname
		}
	}
	
	Context "Reattaches and deletes" {
		$null = Attach-DbaDatabase -SqlInstance localhost -Database $dbname
		$null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
	}
}
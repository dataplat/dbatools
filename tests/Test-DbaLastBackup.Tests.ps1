Describe "Test-DbaLastBackup Integration Tests" -Tags "Integrationtests" {

    Context "Setup removes, restores and backups on the local drive for Test-DbaLastBackup" {
		$null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase

		$null = Restore-DbaDatabase -SqlInstance localhost -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak -WithReplace
		$db = Get-DbaDatabase -SqlInstance localhost -Database singlerestore
		$null = $db | Backup-DbaDatabase -Type Full
		$null = $db | Backup-DbaDatabase -Type Differential
		$null = $db | Backup-DbaDatabase -Type Log
	}
	

    Context "Test a single database" {
        $results = Test-DbaLastBackup -SqlInstance localhost -Database singlerestore
		
        It "Should return success" {
            $results.RestoreResult | Should Be "Success"
        }
	}
	
	Context "Testing the whole instance" {
		$results = Test-DbaLastBackup -SqlInstance localhost -ExcludeDatabase tempdb
		$null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
        It "Should be 5 databases" {
            $results.count | Should Be 5
        }
	}
}
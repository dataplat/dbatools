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
			$results.DbccResult | Should Be "Success"
        }
	}
	
	Context "Testing the whole instance" {
		$results = Test-DbaLastBackup -SqlInstance localhost -ExcludeDatabase tempdb
        It "Should be more than 3 databases" {
            $results.count | Should BeGreaterThan 3
        }
	}
	
	Context "Testing that it restores to a specific path" {
		$null = Test-DbaLastBackup -SqlInstance localhost -Database singlerestore -DataDirectory C:\temp -LogDirectory C:\temp -NoDrop
		$results = Get-DbaDatabaseFile -SqlInstance localhost -Database dbatools-testrestore-singlerestore
		It "Should match C:\temp" {
			('C:\temp\dbatools-testrestore-singlerestore.mdf' -in $results.PhysicalName) | Should Be $true
			('C:\temp\dbatools-testrestore-singlerestore_log.ldf' -in $results.PhysicalName) | Should Be $true
		}
		$null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
	}

	Context "Setup removes, restores and backups on the local drive for Test-DbaLastBackup for multi position tests" {
		$null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase

		$null = Restore-DbaDatabase -SqlInstance localhost -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak -WithReplace
		$db = Get-DbaDatabase -SqlInstance localhost -Database singlerestore
		$null = $db | Backup-DbaDatabase -Type Full -BackupFileName TestLast.bak
		$null = $db | Backup-DbaDatabase -Type Full -BackupFileName TestLast.bak
		$null = $db | Backup-DbaDatabase -Type Differential
		$null = $db | Backup-DbaDatabase -Type Log
	}

	Context "Testing that it works with multiple backups in one file"{
		$results = Test-DbaLastBackup -SqlInstance localhost -Database singlerestore
		
        It "Should return success" {
			$results.RestoreResult | Should Be "Success"
			$results.DbccResult | Should Be "Success"
        }
	}
	
}
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
Describe "Test-DbaLastBackup Integration Tests" -Tags "Integrationtests" {

    Context "Setup removes, restores and backups on the local drive for Test-DbaLastBackup" {
		$null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase

		$null = Restore-DbaDatabase -SqlInstance localhost -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak -WithReplace
		$null = Get-DbaDatabase -SqlInstance localhost -Database singlerestore | Backup-DbaDatabase -Type Full
		$null = Get-DbaDatabase -SqlInstance localhost -Database singlerestore | Backup-DbaDatabase -Type Full
		$null = Get-DbaDatabase -SqlInstance localhost -Database singlerestore | Backup-DbaDatabase -Type Differential
		$null = Get-DbaDatabase -SqlInstance localhost -Database singlerestore | Backup-DbaDatabase -Type Log
		$null = Get-DbaDatabase -SqlInstance localhost -Database singlerestore | Backup-DbaDatabase -Type Log
		$null = Get-DbaDatabase -SqlInstance localhost -Database singlerestore | Backup-DbaDatabase -Type Log
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
	# Try to avoid rando deadlock
	Start-Sleep 3
	
	Context "Testing that it restores to a specific path" {
		$null = Test-DbaLastBackup -SqlInstance localhost -Database singlerestore -DataDirectory C:\temp -LogDirectory C:\temp -NoDrop
		$results = Get-DbaDatabaseFile -SqlInstance localhost -Database dbatools-testrestore-singlerestore
		It "Should match C:\temp" {
			('C:\temp\dbatools-testrestore-singlerestore.mdf' -in $results.PhysicalName) | Should Be $true
			('C:\temp\dbatools-testrestore-singlerestore_log.ldf' -in $results.PhysicalName) | Should Be $true
		}
		
		$null = Get-DbaProcess -SqlInstance localhost -Database dbatools-testrestore-singlerestore | Stop-DbaProcess
		$null = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
	}
}
$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Setup removes, restores and backups on the local drive for Test-DbaLastBackup" {
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase

		$null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path C:\github\appveyor-lab\singlerestore\testlastbackup.bak -WithReplace
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database testlastbackup | Backup-DbaDatabase -Type Full
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database testlastbackup | Backup-DbaDatabase -Type Full
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database testlastbackup | Backup-DbaDatabase -Type Differential
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database testlastbackup -RecoveryModel Full | Backup-DbaDatabase -Type Log
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database testlastbackup -RecoveryModel Full | Backup-DbaDatabase -Type Log
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database testlastbackup -RecoveryModel Full | Backup-DbaDatabase -Type Log
	}
	
	<#
    Context "Test a single database" {
        $results = Test-DbaLastBackup -SqlInstance $script:instance1 -Database testlastbackup
		
        It "Should return success" {
			$results.RestoreResult | Should Be "Success"
			$results.DbccResult | Should Be "Success"
        }
	}
	
	$null = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase
	
	
	Context "Testing the whole instance" {
		$results = Test-DbaLastBackup -SqlInstance $script:instance1 -ExcludeDatabase tempdb
        It "Should be more than 3 databases" {
            $results.count | Should BeGreaterThan 3
        }
	}
	
	Context "Testing that it restores to a specific path" {
		$null = Test-DbaLastBackup -SqlInstance $script:instance1 -Database singlerestore -DataDirectory C:\temp -LogDirectory C:\temp -NoDrop
		$results = Get-DbaDatabaseFile -SqlInstance $script:instance1 -Database dbatools-testrestore-singlerestore
		It "Should match C:\temp" {
			('C:\temp\dbatools-testrestore-singlerestore.mdf' -in $results.PhysicalName) | Should Be $true
			('C:\temp\dbatools-testrestore-singlerestore_log.ldf' -in $results.PhysicalName) | Should Be $true
		}
		
		$null = Get-DbaProcess -SqlInstance $script:instance1 -Database dbatools-testrestore-singlerestore | Stop-DbaProcess
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase
	}
	#>
}
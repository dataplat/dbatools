$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	Context "Setup removes, restores and backups on the local drive for Get-DbaBackupHistory" {
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase
		$null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appeyorlabrepo\singlerestore\singlerestore.bak
		$db = Get-DbaDatabase -SqlInstance $script:instance1 -Database singlerestore
		$db | Backup-DbaDatabase -Type Full
		$db | Backup-DbaDatabase -Type Differential
		$db | Backup-DbaDatabase -Type Log
		$db | Backup-DbaDatabase -Type Log
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database master | Backup-DbaDatabase -Type Full
	}
	
	<#
	Context "Get last history for single database" {
		$results = Get-DbaBackupHistory -SqlInstance $script:instance1 -Database singlerestore -Last
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
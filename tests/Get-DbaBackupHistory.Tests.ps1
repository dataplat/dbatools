$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	BeforeAll {
		$DestBackupDir = 'C:\Temp\backups'
		if (-Not(Test-Path $DestBackupDir)) {
			New-Item -Type Container -Path $DestBackupDir
		}
		$random = Get-Random
		$dbname = "dbatoolsci_history_$random"
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase
		$null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appeyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname -DestinationFilePrefix $dbname
		$db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
		$db | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
		$db | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
		$db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir
		$db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database master | Backup-DbaDatabase -Type Full
	}
	
	AfterAll {
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase
	}
	
	Context "Get last history for single database" {
		$results = Get-DbaBackupHistory -SqlInstance $script:instance1 -Database $dbname -Last
		It "Should be more than one database" {
			$results.count | Should Be 4
		}
	}
	
	Context "Get last history for all databases" {
		$results = Get-DbaBackupHistory -SqlInstance $script:instance1
		It "Should be more than one database" {
			($results | Where-Object Database -match "master").Count | Should BeGreaterThan 0
		}
	}
}
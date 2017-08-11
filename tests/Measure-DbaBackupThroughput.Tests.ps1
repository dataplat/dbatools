$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Returns output for single database" {
		BeforeAll {
			$server = Connect-DbaSqlServer -SqlInstance $script:instance2
			$random = Get-Random
			$db = "dbatoolsci_measurethruput$random"
			$server.Query("CREATE DATABASE $db")
			$null = Get-DbaDatabase -SqlInstance $server -Database $db | Backup-DbaDatabase
		}
		AfterAll {
			$null = Get-DbaDatabase -SqlInstance $server -Database $db | Remove-DbaDatabase
		}
		
		$results = Measure-DbaBackupThroughput -SqlInstance $server -Database $db
		It "Should return just one backup" {
			$results.Database.Count -eq 1 | Should Be $true
		}
	}
}
